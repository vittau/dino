import Foundation
import Observation

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var apiKey: String { didSet { Secrets.apiKey = apiKey } }
    var model: String { didSet { defaults.set(model, forKey: "model") } }
    var spriteScale: Double { didSet { defaults.set(spriteScale, forKey: "spriteScale") } }
    var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: "alwaysOnTop") } }
    var streaming: Bool { didSet { defaults.set(streaming, forKey: "streaming") } }

    var hasAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        LegacyCleanup.runIfNeeded()
        apiKey = Secrets.apiKey
        model = defaults.string(forKey: "model") ?? OpenCodeGo.defaultModel
        spriteScale = defaults.object(forKey: "spriteScale") as? Double ?? 1.0
        alwaysOnTop = defaults.object(forKey: "alwaysOnTop") as? Bool ?? true
        streaming = defaults.object(forKey: "streaming") as? Bool ?? true
    }
}
