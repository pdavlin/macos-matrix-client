import AppKit
@testable import MessageFormatting
import Models
import SwiftUI
import Testing
import Tokens
import UI

/// MATRIX-162: a message body of only emoji, custom emoticons among them,
/// draws at the jumbo size.
///
/// `Models.JumboEmoji.kind` decides (see `JumboEmoticonTests` for the rule).
/// These tests cover the drawing: the square's size, and the height of the
/// body before and after the images load.
@MainActor
struct JumboEmoticonBodyTests {
    private static let parrot = BodyEmoticonTests.parrot

    private func attachments(in string: NSAttributedString) -> [NSTextAttachment] {
        var found: [NSTextAttachment] = []
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment {
                found.append(attachment)
            }
        }
        return found
    }

    private func height(of string: NSAttributedString, width: CGFloat = 300) -> CGFloat {
        let field = NSTextField(labelWithAttributedString: string)
        field.lineBreakMode = .byWordWrapping
        field.usesSingleLineMode = false
        field.preferredMaxLayoutWidth = width
        let bounds = NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)
        return ceil(field.cell?.cellSize(forBounds: bounds).height ?? 0)
    }

    /// The whitespace trim keeps every character of a body with emoji
    /// outside the BMP. It counted `Character`s as UTF-16 units, and cut one
    /// unit off the end for each such emoji.
    @Test func trimKeepsTextAfterEmoji() {
        let trimmed = NSAttributedString(string: " \n\u{1F44D} a \u{1F389}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} done \n").trimmed
        #expect(trimmed.string == "\u{1F44D} a \u{1F389}\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467} done")
        #expect(NSAttributedString(string: "  plain  ").trimmed.string == "plain")
        #expect(NSAttributedString(string: " \n ").trimmed.string == " \n ")

        let body = AttributedTextView(
            attributedString: parseFormattedBody("\u{1F44D}\(Self.parrot)\u{1F389}\(Self.parrot)", imageLoader: EmoticonStubLoader())
        ).attributedString
        #expect(body.string == "\u{1F44D}\u{FFFC}\u{1F389}\u{FFFC}")
        #expect(attachments(in: body).count == 2)
    }

    /// A body of only custom emoticons is a jumbo-emoji message, drawn from
    /// its HTML body. It is not jumbo text: the plain body holds `:name:`.
    @Test func emoticonOnlyBodyIsJumbo() {
        #expect(Models.JumboEmoji.kind(body: ":partyparrot:", formattedBody: Self.parrot) == .formatted)
        #expect(Models.JumboEmoji.jumboText(body: ":partyparrot:", formattedBody: Self.parrot) == nil)
    }

    /// In a jumbo body the square takes its side from the jumbo font, with
    /// and without the image.
    @Test func jumboSquareTakesItsSideFromTheJumboFont() throws {
        let jumboFont = NSFont.systemFont(ofSize: TypographyToken.jumboEmojiSize)
        let side = EmoticonAttachment.side(for: jumboFont)
        #expect(side > TypographyToken.jumboEmojiSize)

        let pending = parseFormattedBody(Self.parrot, baseFontSize: TypographyToken.jumboEmojiSize, imageLoader: EmoticonStubLoader())
        let loaded = parseFormattedBody(
            Self.parrot,
            baseFontSize: TypographyToken.jumboEmojiSize,
            imageLoader: EmoticonStubLoader(colors: ["mxc://example.org/parrot": .stubGreen])
        )
        let pendingAttachment = try #require(attachments(in: pending).first as? EmoticonAttachment)
        let loadedAttachment = try #require(attachments(in: loaded).first as? EmoticonAttachment)
        #expect(!pendingAttachment.isLoaded)
        #expect(loadedAttachment.isLoaded)
        #expect(pendingAttachment.bounds == CGRect(x: 0, y: jumboFont.descender, width: side, height: side))
        #expect(loadedAttachment.bounds == pendingAttachment.bounds)
        // The alt text and the image both fill the square.
        #expect(pendingAttachment.image?.size == CGSize(width: side, height: side))
        #expect(loadedAttachment.image?.size == CGSize(width: side, height: side))
    }

    /// A jumbo body lays out at one height with the alt text and with the
    /// images. A mix with Unicode emoji, and a paragraph around the
    /// emoticons, do not change it. A line of Unicode emoji alone, and a line
    /// of text in the jumbo font, are within a point of it: the square sits
    /// on the font's descender, which the text line rounds.
    @Test func jumboHeightIsTheSameBeforeAndAfterTheImagesLoad() {
        let size = TypographyToken.jumboEmojiSize
        let images = EmoticonStubLoader(colors: ["mxc://example.org/parrot": .stubGreen])
        let oneEmoticon = height(of: parseFormattedBody(Self.parrot, baseFontSize: size, imageLoader: images))
        #expect(abs(oneEmoticon - height(of: parseFormattedBody("xx", baseFontSize: size))) <= 1)
        #expect(abs(oneEmoticon - height(of: parseFormattedBody("\u{1F44D}", baseFontSize: size))) <= 1)
        for html in [
            Self.parrot,
            Self.parrot + Self.parrot + Self.parrot,
            "\u{1F44D} \(Self.parrot) \u{1F389}",
            "<p>\(Self.parrot)</p>",
        ] {
            let pending = height(of: AttributedTextView(
                attributedString: parseFormattedBody(html, baseFontSize: size, imageLoader: EmoticonStubLoader())
            ).attributedString)
            let loaded = height(of: AttributedTextView(
                attributedString: parseFormattedBody(html, baseFontSize: size, imageLoader: images)
            ).attributedString)
            #expect(pending == loaded)
            #expect(pending == oneEmoticon)
        }
    }

    /// The view the row draws and the timeline measures: a jumbo body is one
    /// size before and after its image loads, and taller than at body size.
    @Test func jumboViewSizeDoesNotDependOnTheImage() {
        func size(isJumbo: Bool, loader: EmoticonStubLoader) -> CGSize {
            let controller = NSHostingController(
                rootView: AnyView(
                    FormattedBodyText(html: Self.parrot, baseFontSize: 13, isJumbo: isJumbo, imageLoader: loader)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 300)
                )
            )
            return controller.view.fittingSize
        }
        let images = EmoticonStubLoader(colors: ["mxc://example.org/parrot": .stubGreen])
        let pending = size(isJumbo: true, loader: EmoticonStubLoader())
        #expect(pending == size(isJumbo: true, loader: images))
        #expect(pending.height > size(isJumbo: false, loader: images).height)
        #expect(pending.height >= EmoticonAttachment.side(for: NSFont.systemFont(ofSize: TypographyToken.jumboEmojiSize)))
    }
}
