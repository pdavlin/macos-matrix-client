import Foundation
import Models

/// Takes every `<img>` out of an HTML body before the HTML renderer sees it
/// (MATRIX-153).
///
/// Two outcomes, and no third:
///
/// - A custom emoticon becomes its alt text (else its title) between two
///   marker characters. The renderer carries the markers through as text,
///   and `EmoticonAttachment.resolve` swaps each marked range for a
///   fixed-size attachment. `Models.EmoticonImageTag` reads the tag and says
///   which `<img>` is a custom emoticon: an `mxc://` source with
///   `data-mx-emoticon` or a `:name:` alt or title (MATRIX-159). The same
///   reader counts the emoticons of a jumbo body (MATRIX-162).
/// - Every other `<img>` becomes its alt text, or nothing when it has none.
///
/// So no `<img>` reaches ZMarkupParser, whose default handler downloads
/// `src` with `URLSession.shared` from whatever host the sender names.
enum ImageTagRewriter {
    /// The interlinear annotation anchor and terminator, which message text does not use. Both are
    /// removed from the input first, so a sender cannot forge a marker.
    static let openMarker = "\u{FFF9}"
    static let closeMarker = "\u{FFFB}"

    struct Output: Equatable {
        /// The HTML with no `<img>` in it.
        var html: String
        /// The `mxc://` source of each marked emoticon, in document order.
        var emoticonSources: [String]
        /// The name of each marked emoticon, as its tag gives it: the alt,
        /// else the title. One for each source, in the same order
        /// (MATRIX-161).
        var emoticonNames: [String] = []
    }

    private static let closingTag = try? NSRegularExpression(pattern: #"</img\s*>"#, options: [.caseInsensitive])

    static func rewrite(_ html: String) -> Output {
        let clean = html
            .replacingOccurrences(of: openMarker, with: "")
            .replacingOccurrences(of: closeMarker, with: "")
        guard let imageTag = EmoticonImageTag.tag, let closingTag else {
            // The patterns are constants, so this cannot happen. Fail closed:
            // a body with no markup in it cannot hold an image.
            return Output(html: escapeText(clean), emoticonSources: [])
        }

        let source = clean as NSString
        var result = ""
        var sources: [String] = []
        var names: [String] = []
        var cursor = 0
        for match in imageTag.matches(in: clean, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length

            let attributes = EmoticonImageTag.attributes(source.substring(with: match.range(at: 1)))
            let alt = escapeText(attributes["alt"] ?? "")
            if let emoticonSource = EmoticonImageTag.emoticonSource(attributes) {
                let name = EmoticonImageTag.emoticonName(attributes)
                sources.append(emoticonSource)
                names.append(name)
                result += openMarker + (alt.isEmpty ? escapeText(name) : alt) + closeMarker
            } else {
                result += alt
            }
        }
        result += source.substring(from: cursor)

        let withoutClosing = closingTag.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: (result as NSString).length),
            withTemplate: ""
        )
        return Output(html: withoutClosing, emoticonSources: sources, emoticonNames: names)
    }

    /// An attribute value, made safe as HTML text. Entities stay as they are,
    /// so the renderer decodes them; a raw angle bracket cannot open a tag.
    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
