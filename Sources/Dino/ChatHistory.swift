import Foundation

/// The conversation, kept between launches.
///
/// It lives beside the key in Application Support. Only the visible text is
/// stored - no reasoning traces or token accounting.
enum ChatHistory {
    struct Stored: Codable {
        struct Message: Codable {
            var author: String
            var text: String
            var isError: Bool
        }
        var sessionID: String
        var messages: [Message]
    }

    private static let fileURL = SupportDirectory.file("history.json")

    static func load() -> Stored? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data)
    }

    static func save(_ stored: Stored) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
