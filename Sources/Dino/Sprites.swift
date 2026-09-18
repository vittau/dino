import AppKit

/// Loads the sprite PNGs. The files are shipped in the app bundle, but when
/// running straight from `swift run` there is no bundle, so a couple of
/// development locations are tried too. `DINO_SPRITES_DIR` wins over all of
/// them, which is handy for trying out new art without rebuilding.
enum Sprites {
    static let idle: [NSImage] = (1...8).compactMap { load("idle_\($0)") }
    static let blink: NSImage? = load("blink")

    static var isAvailable: Bool { !idle.isEmpty }

    private static let directories: [URL] = {
        var dirs: [URL] = []
        if let override = ProcessInfo.processInfo.environment["DINO_SPRITES_DIR"] {
            dirs.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent("sprites", isDirectory: true))
        }
        // .build/<config>/Dino -> repo root
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let root = executable.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        dirs.append(root.appendingPathComponent("Resources/sprites", isDirectory: true))
        dirs.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath,
                        isDirectory: true).appendingPathComponent("Resources/sprites", isDirectory: true))
        return dirs
    }()

    private static func load(_ name: String) -> NSImage? {
        for directory in directories {
            let url = directory.appendingPathComponent("\(name).png")
            if FileManager.default.fileExists(atPath: url.path),
               let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return nil
    }
}
