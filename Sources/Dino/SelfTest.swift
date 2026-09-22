import Foundation

/// `Dino --selftest` exercises the OpenCode Go client without opening the
/// window: list models, then stream a reply and fetch a one-shot reply. Handy
/// for checking a key or the SSE parsing without poking at the UI.
enum SelfTest {
    static func runAndExit() -> Never {
        let key = AppSettings.shared.apiKey
        guard !key.isEmpty else {
            print("selftest: nenhuma API key salva ainda")
            exit(2)
        }
        let model = AppSettings.shared.model
        print("selftest: modelo=\(model)")

        Task.detached {
            do {
                let session = OpenCodeGo.newSessionID()
                let models = try await OpenCodeGo.availableModels(apiKey: key, sessionID: session)
                print("selftest: \(models.count) modelos disponíveis")
                print("selftest: primeiros -> \(models.prefix(6).joined(separator: ", "))")

                let turns = [
                    OpenCodeGo.Turn(role: "system", content: Personality.default),
                    OpenCodeGo.Turn(role: "user", content: "diz oi em poucas palavras"),
                ]

                var streamed = ""
                for try await delta in OpenCodeGo.stream(
                    model: model, turns: turns, apiKey: key,
                    sessionID: OpenCodeGo.newSessionID()) {
                    streamed += delta
                }
                print("selftest: stream -> \(streamed)")

                let oneShot = try await OpenCodeGo.complete(
                    model: model, turns: turns, apiKey: key,
                    sessionID: OpenCodeGo.newSessionID(), maxTokens: 200)
                print("selftest: one-shot -> \(oneShot)")

                if streamed.isEmpty {
                    print("selftest: FALHOU (stream vazio)")
                    exit(1)
                }
                print("selftest: OK")
                exit(0)
            } catch {
                print("selftest: FALHOU -> \(error.localizedDescription)")
                exit(1)
            }
        }
        dispatchMain()
    }
}
