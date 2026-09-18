import Foundation

/// Where the app keeps its files: the API key and the saved conversation.
enum SupportDirectory {
    static let url: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dino", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func file(_ name: String) -> URL {
        url.appendingPathComponent(name)
    }
}
