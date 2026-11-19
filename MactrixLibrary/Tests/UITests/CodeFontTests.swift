import AppKit
import MessageFormatting
import SnapshotTesting
import SwiftUI
import Testing
import Tokens

/// MATRIX-202: code text uses the installed code family
/// (`TypographyToken.installedCodeFontFamily`): Berkeley Mono where the user
/// installed it, else Menlo.
@MainActor
struct CodeFontTests {
    enum Body: String, CaseIterable, CustomTestStringConvertible {
        case inlineCode
        case codeBlock

        var testDescription: String { rawValue }

        var html: String {
            switch self {
            case .inlineCode:
                "run <code>scripts/build.sh</code> before you push"
            case .codeBlock:
                "<pre><code>let family = TypographyToken.installedCodeFontFamily\nprint(family ?? \"none\")\n</code></pre>"
            }
        }
    }

    private nonisolated static let berkeleyMonoIsInstalled = TypographyToken.installedCodeFontFamily == "Berkeley Mono"

    /// The font of the first character of `text` in the render of `html`.
    private func font(of text: String, in html: String) -> NSFont? {
        let rendered = parseFormattedBody(html, baseFontSize: CGFloat(TypographyToken.defaultBaseFontSize))
        let range = (rendered.string as NSString).range(of: text)
        guard range.location != NSNotFound else { return nil }
        return rendered.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
    }

    @Test
    func codeUsesTheInstalledFamilyAtTheBodySize() {
        let code = font(of: "build", in: Body.inlineCode.html)
        #expect(code?.familyName == TypographyToken.installedCodeFontFamily)
        #expect(code?.pointSize == CGFloat(TypographyToken.defaultBaseFontSize) * TypographyToken.bodyScale)
        #expect(font(of: "family", in: Body.codeBlock.html)?.familyName == TypographyToken.installedCodeFontFamily)
        #expect(font(of: "before", in: Body.inlineCode.html)?.familyName != TypographyToken.installedCodeFontFamily)
    }

    @Test(.enabled(if: berkeleyMonoIsInstalled))
    func boldAndItalicCodeUseTheBerkeleyMonoFaces() {
        let html = "<code>plain <b>bold</b> <i>oblique</i> <b><i>both</i></b></code>"
        #expect(font(of: "plain", in: html)?.fontName == "BerkeleyMono-Regular")
        #expect(font(of: "bold", in: html)?.fontName == "BerkeleyMono-Bold")
        #expect(font(of: "oblique", in: html)?.fontName == "BerkeleyMono-Oblique")
        #expect(font(of: "both", in: html)?.fontName == "BerkeleyMono-BoldOblique")
    }

    // MARK: Snapshots

    // Recorded on a Mac with Berkeley Mono installed. CI skips them.

    private func body(_ html: String, appearance: NSAppearance.Name) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                FormattedBodyText(
                    html: html,
                    baseFontSize: CGFloat(TypographyToken.defaultBaseFontSize),
                    imageLoader: nil
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 360, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.frame.size = controller.view.fittingSize
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: Body.allCases)
    func codeLight(body: Body) {
        assertSnapshot(of: self.body(body.html, appearance: .aqua), as: .scaledImage(precision: 0.9995), named: body.rawValue)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: Body.allCases)
    func codeDark(body: Body) {
        assertSnapshot(of: self.body(body.html, appearance: .darkAqua), as: .scaledImage(precision: 0.9995), named: body.rawValue)
    }
}
