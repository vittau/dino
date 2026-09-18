import AppKit
import SwiftUI

/// `Dino --render <dir>` draws the widget offscreen to PNGs and exits.
/// It needs no window, no screen-recording permission and no mouse, which
/// makes it the quickest way to check a layout change.
enum RenderHarness {
    @MainActor
    static func runAndExit(into directory: String) -> Never {
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)

        // The glass layer and text fields are NSView-backed and cannot be
        // snapshotted offscreen; everything else is faithful, which is what
        // the balloon and layout checks need.
        RenderMode.offscreen = true

        let store = ChatStore.shared
        store.messages = [
            .init(author: .dino,
                  text: "Oi! Eu sou o Dino 🦕✨ Prontinho pra conversar~ 💚"),
            .init(author: .user, text: "Oiii"),
            .init(author: .dino, text: "Oii~ 🦕"),
            .init(author: .user, text: "Qual a previsão do tempo?"),
            .init(author: .dino,
                  text: "Rawr~ não consigo espiar lá fora daqui do cantinho "
                      + "da tela 🦕🌧️ Me diz sua cidade que eu te ajudo a descobrir?"),
            .init(author: .dino, text: "Ops, deu ruim aqui 😖", isError: true),
        ]

        // Smallest, default and a large shape, to prove the layout flexes.
        let sizes: [(String, CGSize)] = [
            ("widget-min", Metrics.minPanelSize),
            ("widget", Metrics.panelSize),
            ("widget-wide", CGSize(width: 640, height: 760)),
            ("widget-tall", CGSize(width: 380, height: 900)),
        ]
        for (name, size) in sizes {
            render(PetRootView().frame(width: size.width, height: size.height),
                   to: "\(directory)/\(name).png")
        }

        render(gallery.padding(20), to: "\(directory)/balloons.png")

        render(breathStrip.padding(16), to: "\(directory)/breath.png")

        print("render: wrote \(sizes.count + 2) files into \(directory)")
        exit(0)
    }

    /// Every frame side by side, to check the anchoring holds across the sheet.
    private static var breathStrip: some View {
        HStack(spacing: 0) {
            ForEach(Array(Sprites.idle.indices), id: \.self) { index in
                DinoFrames(frame: index)
                    .frame(width: 118, height: 118)
            }
        }
        .background(Color.white)
    }

    /// Balloons with the shortest and longest messages, to catch tails and
    /// text being clipped at the extremes.
    private static var gallery: some View {
        VStack(alignment: .leading, spacing: 10) {
            BalloonRow(message: .init(author: .user, text: "Oi"))
            BalloonRow(message: .init(author: .dino, text: "Oi"))
            BalloonRow(message: .init(author: .user, text: "Oiii"))
            BalloonRow(message: .init(author: .dino, text: "Oiii"))
            BalloonRow(message: .init(author: .user, text: "a"))
            BalloonRow(message: .init(author: .dino, text: "🦕"))
            BalloonRow(message: .init(author: .user, text: "Qual a previsão do tempo?"))
            BalloonRow(message: .init(author: .dino,
                                      text: "Rawr~ não consigo espiar lá fora daqui "
                                          + "do cantinho da tela 🦕🌧️"))
        }
        .frame(width: Metrics.content.width)
        .background(Color.white)
    }

    @MainActor
    private static func render(_ view: some View, to path: String) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render: failed to render \(path)")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
