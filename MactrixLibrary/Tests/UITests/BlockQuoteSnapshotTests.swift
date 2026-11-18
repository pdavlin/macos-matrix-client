import AppKit
import MessageFormatting
import SnapshotTesting
import SwiftUI
import Testing
import Tokens

/// MATRIX-192: the block quote bodies of `BlockQuoteBodyTests`, in light and
/// dark mode. Each body shows all of its lines, and the quote lines indent
/// and have the secondary text color (`BlockQuoteToken`).
///
/// Snapshot references render at a fixed 2x through `.scaledImage` (S-26).
@MainActor
struct BlockQuoteSnapshotTests {
    private func body(_ html: String, appearance: NSAppearance.Name) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                FormattedBodyText(
                    html: html,
                    baseFontSize: CGFloat(TypographyToken.defaultBaseFontSize),
                    imageLoader: nil
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: BlockQuoteBodyTests.width, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.frame.size = controller.view.fittingSize
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: BlockQuoteBodyTests.Body.allCases)
    func quoteLight(body: BlockQuoteBodyTests.Body) {
        assertSnapshot(of: self.body(body.html, appearance: .aqua), as: .scaledImage(precision: 0.9995), named: body.rawValue)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: BlockQuoteBodyTests.Body.allCases)
    func quoteDark(body: BlockQuoteBodyTests.Body) {
        assertSnapshot(of: self.body(body.html, appearance: .darkAqua), as: .scaledImage(precision: 0.9995), named: body.rawValue)
    }
}
