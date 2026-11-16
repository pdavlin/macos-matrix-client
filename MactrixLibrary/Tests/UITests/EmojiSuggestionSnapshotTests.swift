import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-156: the composer's custom emoji completion list. The loader
/// holds one solid-color image per URL in its cache, so the rows draw
/// without a network. Local gate only, as the other snapshots (contract R-8).
@MainActor
struct EmojiSuggestionSnapshotTests {
    /// Serves a solid-color square for each known URL, from the cache.
    private struct SwatchLoader: ImageLoader {
        let colors: [String: NSColor]

        func cachedImage(matrixUrl: String) -> Image? {
            guard let color = colors[matrixUrl] else { return nil }
            let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
                color.setFill()
                rect.fill()
                return true
            }
            return Image(nsImage: image)
        }

        func loadImage(matrixUrl: String, size _: CGSize?) async throws -> Image? {
            cachedImage(matrixUrl: matrixUrl)
        }
    }

    private static let loader = SwatchLoader(colors: [
        "mxc://a/parrot": .systemGreen,
        "mxc://a/party": .systemPurple,
        "mxc://a/paris": .systemOrange,
    ])

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func suggestionList() {
        let list = EmojiSuggestionList(
            suggestions: [
                ImagePackEmoji(shortcode: "parrot", url: "mxc://a/parrot"),
                ImagePackEmoji(shortcode: "paris", url: "mxc://a/paris"),
                ImagePackEmoji(shortcode: "party_parrot", url: "mxc://a/party"),
            ],
            selectedIndex: 1,
            imageLoader: Self.loader,
            onPick: { _ in }
        )
        .frame(width: 360)
        .background(Color.white)
        let controller = NSHostingController(rootView: list)
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        assertSnapshot(of: controller, as: .scaledImage)
    }
}
