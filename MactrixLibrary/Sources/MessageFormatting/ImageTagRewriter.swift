import Foundation

/// Takes every `<img>` out of an HTML body before the HTML renderer sees it
/// (MATRIX-153).
///
/// Two outcomes, and no third:
///
/// - A custom emoticon becomes its alt text (else its title) between two
///   marker characters. The renderer carries the markers through as text,
///   and `EmoticonAttachment.resolve` swaps each marked range for a
///   fixed-size attachment. An `<img>` is a custom emoticon when its source
///   is a well-formed `mxc://server/mediaId` URL and it has
///   `data-mx-emoticon`, or an alt of the form `:name:`, or no alt and a
///   title of that form. The SDK timeline removes `data-mx-emoticon` from
///   the body it gives back (MATRIX-159), so the attribute cannot be the
///   only signal.
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

    /// `<img …>` with quoted attribute values that may hold a `>`.
    private static let imageTag = makeExpression(#"<img\b((?:[^>"']|"[^"]*"|'[^']*')*)>"#)
    private static let closingTag = makeExpression(#"</img\s*>"#)
    /// `name`, `name=value`, `name="value"`, `name='value'`.
    private static let attribute = makeExpression(#"([^\s"'=<>/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?"#)

    private static func makeExpression(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    static func rewrite(_ html: String) -> Output {
        let clean = html
            .replacingOccurrences(of: openMarker, with: "")
            .replacingOccurrences(of: closeMarker, with: "")
        guard let imageTag, let closingTag else {
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

            let attributes = parseAttributes(source.substring(with: match.range(at: 1)))
            let alt = escapeText(attributes["alt"] ?? "")
            if let emoticonSource = emoticonSource(attributes) {
                let name = emoticonName(attributes)
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

    /// `mxc://server/mediaId`, with nothing after the media ID.
    private static let matrixContentURL = makeExpression(#"\Amxc://[^/\s?#]+/[^/\s?#]+\z"#)
    /// `:name:`, where the name has no whitespace and no colon.
    private static let shortcode = makeExpression(#"\A:[^\s:]+:\z"#)

    private static func matches(_ expression: NSRegularExpression?, _ text: String) -> Bool {
        guard let expression else { return false }
        return expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// The `mxc://` source, when the tag is a custom emoticon. A source with
    /// any other scheme never counts, whatever else the tag says.
    private static func emoticonSource(_ attributes: [String: String]) -> String? {
        guard let source = attributes["src"] else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(matrixContentURL, trimmed) else { return nil }
        if attributes["data-mx-emoticon"] != nil { return trimmed }
        return matches(shortcode, emoticonName(attributes)) ? trimmed : nil
    }

    /// The text shown for an emoticon, and its name: the alt, else the title.
    private static func emoticonName(_ attributes: [String: String]) -> String {
        let alt = attributes["alt"] ?? ""
        return alt.isEmpty ? attributes["title"] ?? "" : alt
    }

    /// Attribute names in lower case. The first use of a name wins, as in HTML.
    private static func parseAttributes(_ text: String) -> [String: String] {
        guard let attribute else { return [:] }
        let source = text as NSString
        var attributes: [String: String] = [:]
        for match in attribute.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            let name = source.substring(with: match.range(at: 1)).lowercased()
            guard attributes[name] == nil else { continue }
            let valueRange = [2, 3, 4].map { match.range(at: $0) }.first { $0.location != NSNotFound }
            attributes[name] = valueRange.map { source.substring(with: $0) } ?? ""
        }
        return attributes
    }

    /// An attribute value, made safe as HTML text. Entities stay as they are,
    /// so the renderer decodes them; a raw angle bracket cannot open a tag.
    private static func escapeText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
