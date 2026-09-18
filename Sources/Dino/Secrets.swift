import Foundation

/// The API key lives next to the app's other support files, readable only by
/// the user. Keychain would be the tidier home, but ad-hoc signed builds get a
/// new identity on every rebuild, so the keychain prompt would fire each time.
/// 0600 in Application Support keeps it out of other accounts' reach.
enum Secrets {
    private static let key = "opencodeGoAPIKey"

    private static let fileURL = SupportDirectory.file("secrets.json")

    private static func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return parsed
    }

    private static func store(_ values: [String: String]) {
        guard let data = try? JSONSerialization.data(
            withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static var apiKey: String {
        get { load()[key] ?? "" }
        set {
            var values = load()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                values.removeValue(forKey: key)
            } else {
                values[key] = trimmed
            }
            store(values)
        }
    }

    static var location: URL { fileURL }
}
