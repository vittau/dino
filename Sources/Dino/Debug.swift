import Foundation

/// Diagnostics gated behind `DINO_DEBUG=1`, so a normal run stays quiet.
enum Debug {
    static let enabled = ProcessInfo.processInfo.environment["DINO_DEBUG"] != nil

    static func log(_ message: String) {
        guard enabled else { return }
        FileHandle.standardError.write(Data("[dino] \(message)\n".utf8))
    }
}
