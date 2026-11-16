import AppKit
@testable import MessageFormatting
import SwiftUI
import Testing
import UI

/// MATRIX-159: which `<img>` is a custom emoticon. The SDK timeline removes
/// `data-mx-emoticon` from the body it gives back, so the attribute is not
/// the only signal.
@MainActor
struct BodyEmoticonRuleTests {
    private func attachments(in string: NSAttributedString) -> [NSTextAttachment] {
        var found: [NSTextAttachment] = []
        string.enumerateAttribute(.attachment, in: NSRange(location: 0, length: string.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment {
                found.append(attachment)
            }
        }
        return found
    }

    /// The exact tag the SDK timeline gives back for a sent emoticon: no
    /// `data-mx-emoticon`, attributes in alphabetical order, not self-closed.
    static let sanitized = #"<img alt=":party:" height="32" src="mxc://davlin.io/abc" title=":party:">"#

    /// MATRIX-161: the body reports each emoticon's name with its source,
    /// from the same parse, for the learned emoji.
    @Test func theBodyGivesEachEmoticonsNameAndSourceOnce() {
        let titled = #"<img data-mx-emoticon src="mxc://davlin.io/def" title=":shipit:">"#
        let plain = #"<img src="https://example.org/a.png" alt=":nope:">"#
        let html = "a \(Self.sanitized) b \(titled) c \(plain) d \(Self.sanitized)"

        #expect(emoticons(inFormattedBody: html) == [
            BodyEmoticon(name: ":party:", source: "mxc://davlin.io/abc"),
            BodyEmoticon(name: ":shipit:", source: "mxc://davlin.io/def"),
        ])
        #expect(emoticonSources(inFormattedBody: html) == ["mxc://davlin.io/abc", "mxc://davlin.io/def"])
        #expect(emoticons(inFormattedBody: "<p>no image</p>").isEmpty)
    }

    @Test func sanitizedEmoticonIsAnEmoticon() throws {
        let output = ImageTagRewriter.rewrite("ship it \(Self.sanitized) now")
        #expect(output.html == "ship it \u{FFF9}:party:\u{FFFB} now")
        #expect(output.emoticonSources == ["mxc://davlin.io/abc"])

        let loader = EmoticonStubLoader()
        let rendered = parseFormattedBody("<p>ship it \(Self.sanitized)</p>", imageLoader: loader)
        let attachment = try #require(attachments(in: rendered).first as? EmoticonAttachment)
        #expect(attachment.source == "mxc://davlin.io/abc")
        #expect(attachment.alt == ":party:")
        #expect(loader.cacheRequests == ["mxc://davlin.io/abc"])
        #expect(loader.loadRequests.isEmpty)
    }

    @Test(arguments: [
        #"<img alt=":party:" height="32" src="mxc://davlin.io/abc" title=":party:"/>"#,
        #"<img alt=":party:" height="32" src="mxc://davlin.io/abc" title=":party:" />"#,
        #"<img alt=":party:" height="32" src="mxc://davlin.io/abc" title=":party:"></img>"#,
        #"<img src="mxc://davlin.io/abc" title=":party:" height="32" alt=":party:">"#,
        #"<img title=':party:' src='mxc://davlin.io/abc' alt=':party:' height='32'>"#,
        #"<img alt=":party:" height=32 src="mxc://davlin.io/abc">"#,
        #"<img alt=:party: height=32 src=mxc://davlin.io/abc>"#,
        #"<IMG ALT=":party:" SRC="mxc://davlin.io/abc">"#,
        #"<img height="32" src="mxc://davlin.io/abc" title=":party:">"#,
        #"<img alt="" src="mxc://davlin.io/abc" title=":party:">"#,
        #"<img data-mx-emoticon src="mxc://davlin.io/abc" alt=":party:" title="a party">"#,
    ])
    func emoticonFormsAreEmoticons(tag: String) {
        let output = ImageTagRewriter.rewrite(tag)
        #expect(output.html == "\u{FFF9}:party:\u{FFFB}")
        #expect(output.emoticonSources == ["mxc://davlin.io/abc"])
    }

    /// The marker attribute still makes an emoticon of any alt text.
    @Test func markedEmoticonKeepsOrdinaryAlt() {
        let output = ImageTagRewriter.rewrite(#"<img data-mx-emoticon src="mxc://davlin.io/abc" alt="party">"#)
        #expect(output.html == "\u{FFF9}party\u{FFFB}")
        #expect(output.emoticonSources == ["mxc://davlin.io/abc"])
    }

    /// An `mxc://` image that does not read as a shortcode is an ordinary
    /// image: alt text only.
    @Test(arguments: [
        (#"<img src="mxc://davlin.io/abc" alt="a photo">"#, "a photo"),
        (#"<img src="mxc://davlin.io/abc">"#, ""),
        (#"<img src="mxc://davlin.io/abc" alt="a photo" title=":party:">"#, "a photo"),
        (#"<img src="mxc://davlin.io/abc" alt="party">"#, "party"),
        (#"<img src="mxc://davlin.io/abc" alt=":party">"#, ":party"),
        (#"<img src="mxc://davlin.io/abc" alt="::">"#, "::"),
        (#"<img src="mxc://davlin.io/abc" alt=":a:b:">"#, ":a:b:"),
        (#"<img src="mxc://davlin.io/abc" alt=":a b:">"#, ":a b:"),
        (#"<img src="mxc://davlin.io/abc" alt=" :party: ">"#, " :party: "),
        (#"<img src="mxc://davlin.io/abc" alt="see :party:">"#, "see :party:"),
        ("<img src=\"mxc://davlin.io/abc\" alt=\":party:\n\">", ":party:\n"),
        (#"<img src="mxc://davlin.io" alt=":party:">"#, ":party:"),
        (#"<img src="mxc://davlin.io/" alt=":party:">"#, ":party:"),
        (#"<img src="https://tracker.example/e.png" alt=":party:">"#, ":party:"),
        (#"<img src="https://tracker.example/e.png" title=":party:">"#, ""),
    ])
    func ordinaryImagesStayAltText(tag: String, text: String) {
        let output = ImageTagRewriter.rewrite(tag)
        #expect(output.html == text)
        #expect(output.emoticonSources.isEmpty)
    }

    /// A shortcode alt does not make a remote or malformed source loadable.
    @Test(arguments: [
        #"<p>a <img alt=":party:" height="32" src="https://tracker.example/e.png" title=":party:"> b</p>"#,
        #"<p>a <img alt=":party:" src="mxc://davlin.io/"> b</p>"#,
        #"<p>a <img alt=":party:" src="mxc://davlin.io"> b</p>"#,
        #"<p>a <img alt="a photo" src="mxc://davlin.io/abc"> b</p>"#,
    ])
    func shortcodeAltStartsNoLoad(html: String) async throws {
        let loader = EmoticonStubLoader()
        let rendered = parseFormattedBody(html, imageLoader: loader)
        #expect(attachments(in: rendered).isEmpty)
        #expect(emoticonSources(inFormattedBody: html).isEmpty)

        // The view too: it asks the loader for nothing.
        let controller = NSHostingController(
            rootView: AnyView(FormattedBodyText(html: html, baseFontSize: 13, imageLoader: loader).frame(width: 300))
        )
        let window = NSWindow(contentViewController: controller)
        defer { window.close() }
        controller.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        #expect(loader.cacheRequests.isEmpty)
        #expect(loader.loadRequests.isEmpty)
    }
}
