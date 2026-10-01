import Foundation

/// Thin client for OpenRouter's OpenAI-compatible chat completions API.
enum OpenRouter {
    static let defaultModel = "openrouter/free"
    static let userAgent = "dino/0.1 (macOS)"

    private static let base = URL(string: "https://openrouter.ai/api/v1")!

    struct APIError: LocalizedError {
        let message: String
        /// HTTP status when the failure came from the server, nil otherwise.
        let status: Int?

        init(message: String, status: Int? = nil) {
            self.message = message
            self.status = status
        }

        var errorDescription: String? { message }
    }

    struct Turn {
        let role: String   // "system" | "user" | "assistant"
        let content: String
    }

    static func newSessionID() -> String {
        "ses_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    /// Idle timeout for the quick calls (`availableModels`): if the server does
    /// not answer within 10s the widget goes "offline" instead of leaving the
    /// user staring at a spinner.
    private static let quickTimeout: TimeInterval = 10
    /// Idle timeout for chat completions. A non-streaming reply (or one from a
    /// reasoning model that thinks before its first token) receives nothing
    /// until it is done, so the 10s idle timeout would cut it off; a long
    /// generation gets plenty of room here.
    private static let chatTimeout: TimeInterval = 120

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["User-Agent": userAgent]
        // Fallback for requests that do not set their own timeout: quick calls
        // fail fast (key validation, connection failures), so the widget goes
        // "offline" promptly when the server is unreachable. Chat completions
        // override this with `chatTimeout` so long generations are not cut off.
        config.timeoutIntervalForRequest = quickTimeout
        return URLSession(configuration: config)
    }()

    // MARK: - request building

    private static func request(path: String, apiKey: String,
                                body: [String: Any]?,
                                timeout: TimeInterval) throws -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.timeoutInterval = timeout
        req.httpMethod = body == nil ? "GET" : "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://github.com/vittau/dino", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Dino", forHTTPHeaderField: "X-Title")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private static func message(from data: Data, status: Int) -> String {
        if let err = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            return err.error.message
        }
        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return "Erro \(status): \(text.prefix(300))"
        }
        return "Erro \(status) ao falar com o OpenRouter."
    }

    // MARK: - key and models

    /// /models can be public, so only /key actually validates a user's key.
    static func validateKey(apiKey: String) async throws {
        let req = try request(path: "key", apiKey: apiKey,
                              body: nil, timeout: quickTimeout)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw APIError(message: message(from: data, status: status), status: status)
        }
    }

    /// The /models payload shape has changed before, so accept both the
    /// OpenAI-style envelope and a bare array of objects.
    static func availableModels(apiKey: String) async throws -> [String] {
        let req = try request(path: "models", apiKey: apiKey,
                              body: nil, timeout: quickTimeout)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw APIError(message: message(from: data, status: status), status: status) }

        if let envelope = try? JSONDecoder().decode(ModelEnvelope.self, from: data) {
            return envelope.data.map(\.id).sorted()
        }
        if let models = try? JSONDecoder().decode([Model].self, from: data) {
            return models.map(\.id).sorted()
        }
        throw APIError(message: "Não entendi a lista de modelos que o servidor mandou.")
    }

    // MARK: - chat

    /// Streams reply deltas as they arrive.
    static func stream(model: String, turns: [Turn], apiKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let req = try request(
                        path: "chat/completions", apiKey: apiKey,
                        body: [
                            "model": model,
                            "messages": turns.map { ["role": $0.role, "content": $0.content] },
                            "stream": true,
                        ],
                        timeout: chatTimeout)
                    let (bytes, response) = try await session.bytes(for: req)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard status == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw APIError(message: message(from: data, status: status), status: status)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        if let failure = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
                            throw APIError(message: failure.error.message)
                        }
                        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data)
                        else { continue }
                        if let text = chunk.choices.first?.delta.content, !text.isEmpty {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One-shot variant, used by non-streaming chat replies (no cap, so the
    /// server default applies) and by `--selftest`, which passes a small
    /// `maxTokens` to keep the check cheap.
    static func complete(model: String, turns: [Turn], apiKey: String,
                         maxTokens: Int? = nil) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "messages": turns.map { ["role": $0.role, "content": $0.content] },
            "stream": false,
        ]
        if let maxTokens { body["max_tokens"] = maxTokens }
        let req = try request(
            path: "chat/completions", apiKey: apiKey,
            body: body,
            timeout: chatTimeout)
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw APIError(message: message(from: data, status: status), status: status) }
        guard let reply = try? JSONDecoder().decode(Completion.self, from: data),
              let text = reply.choices.first?.message.content
        else { throw APIError(message: "Resposta vazia do servidor.") }
        return text
    }

    // MARK: - wire types

    private struct ErrorEnvelope: Decodable {
        struct Inner: Decodable {
            let message: String
        }
        let error: Inner
    }

    private struct Model: Decodable {
        let id: String
    }

    private struct ModelEnvelope: Decodable {
        let data: [Model]
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    private struct Completion: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}
