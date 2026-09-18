import Foundation
import Observation

@MainActor
@Observable
final class ChatStore {
    struct Message: Identifiable, Equatable {
        enum Author { case user, dino }

        let id = UUID()
        var author: Author
        var text: String
        var isStreaming = false
        var isError = false
    }

    static let shared = ChatStore()

    private let settings = AppSettings.shared
    private static let historyLimit = 24

    var messages: [Message] = []
    var draft = ""
    var keyDraft = ""
    var isBusy = false
    /// True after a request could not reach the server (timeout or no network).
    /// Drives the red "offline" pill in the header until the next success.
    var isOffline = false
    var isValidatingKey = false
    /// Set when the server rejects the key, so we ask again without forgetting
    /// whatever the user already typed.
    var authFailed = false
    var sessionID = OpenCodeGo.newSessionID()
    private var persistTask: Task<Void, Never>?

    /// True while the dino still needs a key: first run, or a rejected one.
    /// This is what turns the input row into a key field.
    var needsKey: Bool { !settings.hasAPIKey || authFailed }

    private init() {
        if let stored = ChatHistory.load() {
            sessionID = stored.sessionID
            messages = stored.messages.map {
                Message(author: $0.author == "user" ? .user : .dino,
                        text: $0.text,
                        isError: $0.isError)
            }
        }
        if messages.isEmpty {
            messages = [Message(author: .dino,
                                text: settings.hasAPIKey ? Self.greeting : Self.keyRequest)]
        }
    }

    /// Writes the conversation out. Streaming appends a token at a time, so
    /// callers debounce rather than saving on every delta.
    private func persist() {
        ChatHistory.save(ChatHistory.Stored(
            sessionID: sessionID,
            messages: messages
                .filter { !$0.isStreaming }
                .map { ChatHistory.Stored.Message(
                    author: $0.author == .user ? "user" : "dino",
                    text: $0.text,
                    isError: $0.isError) }))
    }

    private func persistSoon() {
        persistTask?.cancel()
        persistTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            persist()
        }
    }

    // MARK: - copy

    private static let greeting =
        "Oi! Eu sou o Dino 🦕✨ Tô aqui no seu cantinho, prontinho pra conversar. Manda o que quiser~ 💚"

    private static let keyRequest =
        "Oi! Eu sou o Dino 🦕✨ Pra gente conversar, eu preciso da sua API key do OpenCode Go. Cola ela aqui embaixo que eu guardo pra você~ 🔑"

    private static let keySaved =
        "Uhuu! Guardei sua chave 🎉 Agora pode me perguntar qualquer coisa~ 🦖💚"

    private static let offlineMessage = """
    Ops! 🥺 Parece que meu cérebro digital deu uma tropeçada e eu não consegui falar com o servidor.

    Tenta de novo daqui a pouquinho? Prometo que não foi o meteoro. 🦖☄️
    """

    // MARK: - onboarding

    func submitKey() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, !isValidatingKey else { return }
        isValidatingKey = true
        isOffline = false
        let sid = sessionID

        Task {
            do {
                let models = try await OpenCodeGo.availableModels(apiKey: candidate, sessionID: sid)
                // Saving through AppSettings is the same write the Settings
                // window does, so the key behaves identically either way.
                settings.apiKey = candidate
                if !models.isEmpty, !models.contains(settings.model) {
                    settings.model = models[0]
                }
                keyDraft = ""
                authFailed = false
                isOffline = false
                isValidatingKey = false
                messages.append(Message(author: .dino, text: Self.keySaved))
                persist()
            } catch {
                isValidatingKey = false
                if Self.isServerUnavailable(error) {
                    isOffline = true
                    messages.append(Message(
                        author: .dino, text: Self.offlineMessage, isError: true))
                } else {
                    authFailed = true
                    messages.append(Message(
                        author: .dino,
                        text: "Hmm, essa chave não funcionou 😢 \(Self.describe(error)) Tenta de novo~ 🔑",
                        isError: true))
                }
            }
        }
    }

    // MARK: - chat

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy, !needsKey else { return }
        draft = ""
        messages.append(Message(author: .user, text: text))

        let replyAt = messages.count
        messages.append(Message(author: .dino, text: "", isStreaming: true))
        isBusy = true
        isOffline = false
        persistSoon()

        let turns = conversation()
        let model = settings.model
        let apiKey = settings.apiKey
        let sid = sessionID
        let streaming = settings.streaming

        Task {
            do {
                var got = false
                if streaming {
                    for try await delta in OpenCodeGo.stream(
                        model: model, turns: turns, apiKey: apiKey, sessionID: sid) {
                        got = true
                        append(delta, at: replyAt)
                    }
                } else {
                    let reply = try await OpenCodeGo.complete(
                        model: model, turns: turns, apiKey: apiKey, sessionID: sid)
                    got = true
                    append(reply, at: replyAt)
                }
                if !got {
                    append("rawr? acho que me perdi aqui 🦖", at: replyAt)
                }
                isOffline = false
                if replyAt < messages.count {
                    messages[replyAt].isStreaming = false
                }
            } catch {
                fail(error, at: replyAt)
            }
            isBusy = false
            persist()
        }
    }

    func newChat() {
        sessionID = OpenCodeGo.newSessionID()
        authFailed = false
        messages = [Message(
            author: .dino,
            text: settings.hasAPIKey ? Self.greeting : Self.keyRequest)]
        persist()
    }

    func clearChat() {
        messages = []
        ChatHistory.clear()
    }

    // MARK: - plumbing

    /// System prompt plus recent history. The in-flight placeholder is skipped
    /// via `isStreaming`, so this can be built after appending it.
    private func conversation() -> [OpenCodeGo.Turn] {
        var turns = [OpenCodeGo.Turn(role: "system", content: Personality.default)]
        let history = messages
            .filter { !$0.isStreaming && !$0.isError && !$0.text.isEmpty }
            .suffix(Self.historyLimit)
        for message in history {
            turns.append(OpenCodeGo.Turn(
                role: message.author == .user ? "user" : "assistant",
                content: message.text))
        }
        return turns
    }

    private func append(_ delta: String, at index: Int) {
        guard index < messages.count else { return }
        messages[index].text += delta
    }

    private func fail(_ error: Error, at index: Int) {
        if Self.isAuthFailure(error) {
            authFailed = true
            if index < messages.count {
                messages[index] = Message(
                    author: .dino,
                    text: "Acho que sua API key expirou ou tá errada 😢 Cola de novo aqui embaixo~ 🔑",
                    isError: true)
            }
            return
        }
        if Self.isServerUnavailable(error) {
            isOffline = true
            if index < messages.count {
                messages[index] = Message(
                    author: .dino, text: Self.offlineMessage, isError: true)
            }
            return
        }
        if index < messages.count {
            messages[index] = Message(
                author: .dino, text: "Ops, deu ruim aqui 😖 \(Self.describe(error))",
                isError: true)
        }
    }

    /// Timeout, no route to the server, or a server-side 5xx - the cases the
    /// header reports as "offline" rather than as a chat error.
    private static func isServerUnavailable(_ error: Error) -> Bool {
        if let api = error as? OpenCodeGo.APIError, let status = api.status, status >= 500 {
            return true
        }
        guard let url = error as? URLError else { return false }
        switch url.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static func isAuthFailure(_ error: Error) -> Bool {
        let text = "\(error.localizedDescription)".lowercased()
        return text.contains("401") || text.contains("403")
            || text.contains("unauthor") || text.contains("invalid api key")
            || text.contains("api key") && text.contains("invalid")
    }

    private static func describe(_ error: Error) -> String {
        if let api = error as? OpenCodeGo.APIError { return api.message }
        if (error as? URLError) != nil {
            return "Não consegui falar com o servidor. Tá sem internet?"
        }
        return error.localizedDescription
    }
}
