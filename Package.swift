// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dino",
    // macOS 15 for NSCursor.frameResize(position:directions:), the resize
    // cursor on the corner grip. There are no SwiftUI scenes here.
    platforms: [.macOS(.v15)],
    // Swift 5 language mode: this is UI code driving AppKit, and strict
    // concurrency buys nothing here but noise.
    targets: [
        .executableTarget(
            name: "Dino",
            path: "Sources/Dino"
        )
    ],
    swiftLanguageModes: [.v5]
)
