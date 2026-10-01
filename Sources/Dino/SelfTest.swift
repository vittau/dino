import Foundation

/// `Dino --selftest` exercises the OpenRouter client without opening the
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
                try await OpenRouter.validateKey(apiKey: key)
                let models = try await OpenRouter.availableModels(apiKey: key)
                print("selftest: \(models.count) modelos disponíveis")
                print("selftest: primeiros -> \(models.prefix(6).joined(separator: ", "))")

                let turns = [
                    OpenRouter.Turn(role: "system", content: await LiveContext.shared.prompt()),
                    OpenRouter.Turn(role: "user", content: "diz oi em poucas palavras"),
                ]

                var streamed = ""
                for try await delta in OpenRouter.stream(
                    model: model, turns: turns, apiKey: key) {
                    streamed += delta
                }
                print("selftest: stream -> \(streamed)")

                let oneShot = try await OpenRouter.complete(
                    model: model, turns: turns, apiKey: key, maxTokens: 200)
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
