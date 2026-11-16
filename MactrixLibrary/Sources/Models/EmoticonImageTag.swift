import Foundation

/// Reads an HTML `<img>` tag and says whether it is a custom emoticon
/// (MATRIX-153, MATRIX-159).
///
/// An `<img>` is a custom emoticon when its source is a well-formed
/// `mxc://server/mediaId` URL and it has `data-mx-emoticon`, or an alt of the
/// form `:name:`, or no alt and a title of that form. The SDK timeline removes
/// `data-mx-emoticon` from the body it gives back, so the attribute cannot be
/// the only signal.
///
/// This is the one place that reads the tag. The HTML body renderer
/// (`ImageTagRewriter`) uses it to draw the emoticon, and `JumboEmoji` uses it
/// to count the emoticons of a body (MATRIX-162), so the two cannot disagree.
public enum EmoticonImageTag {
    /// `<img …>` with quoted attribute values that may hold a `>`. Group 1 is
    /// the attribute text.
    public static let tag = makeExpression(#"<img\b((?:[^>"']|"[^"]*"|'[^']*')*)>"#)
    /// `name`, `name=value`, `name="value"`, `name='value'`.
    private static let attribute = makeExpression(#"([^\s"'=<>/]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?"#)
    /// `mxc://server/mediaId`, with nothing after the media ID.
    private static let matrixContentURL = makeExpression(#"\Amxc://[^/\s?#]+/[^/\s?#]+\z"#)
    /// `:name:`, where the name has no whitespace and no colon.
    private static let shortcode = makeExpression(#"\A:[^\s:]+:\z"#)

    private static func makeExpression(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func matches(_ expression: NSRegularExpression?, _ text: String) -> Bool {
        guard let expression else { return false }
        return expression.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    /// Whether `text` is one whole `<img …>` tag, from `<` to `>`, of a
    /// custom emoticon. False for any other tag, and for a tag with text
    /// before or after it.
    public static func isEmoticon(tag text: String) -> Bool {
        guard let tag else { return false }
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        guard let match = tag.firstMatch(in: text, options: [.anchored], range: whole), match.range == whole else {
            return false
        }
        return emoticonSource(attributes(source.substring(with: match.range(at: 1)))) != nil
    }

    /// The `mxc://` source, when the tag is a custom emoticon. A source with
    /// any other scheme never counts, whatever else the tag says.
    public static func emoticonSource(_ attributes: [String: String]) -> String? {
        guard let source = attributes["src"] else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard matches(matrixContentURL, trimmed) else { return nil }
        if attributes["data-mx-emoticon"] != nil { return trimmed }
        return matches(shortcode, emoticonName(attributes)) ? trimmed : nil
    }

    /// The text shown for an emoticon, and its name: the alt, else the title.
    public static func emoticonName(_ attributes: [String: String]) -> String {
        let alt = attributes["alt"] ?? ""
        return alt.isEmpty ? attributes["title"] ?? "" : alt
    }

    /// The attributes of a tag, from its attribute text (group 1 of `tag`).
    /// Attribute names in lower case. The first use of a name wins, as in HTML.
    public static func attributes(_ text: String) -> [String: String] {
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
}
