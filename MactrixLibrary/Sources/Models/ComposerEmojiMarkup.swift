import Foundation

/// Turns the `:name:` tokens of a message into custom emoji at send time
/// (MATRIX-156).
///
/// The draft is plain text. At send, each `:name:` that is a shortcode of the
/// target room's image packs becomes an emoticon tag in the message markdown:
///
/// ```html
/// <img data-mx-emoticon src="mxc://…" alt=":name:" title=":name:" height="32" />
/// ```
///
/// The SDK's markdown call keeps raw HTML, so the tag reaches
/// `formatted_body`, and the Slack bridge posts an `<img>` with a known `src`
/// as that Slack emoji (`docs/research/slack-custom-emoji.md`, A3). The SDK
/// has no call that gives the HTML of a markdown text back, so the tag goes
/// into the markdown and the SDK makes the HTML, as for every other message.
///
/// Rules:
/// - Only a shortcode of the given packs resolves, by exact match. All other
///   text stays as typed. With no resolved token the result is the input.
/// - Text in a code span, a fenced or indented code block, a link
///   destination, an autolink or an HTML tag, and text after a backslash is
///   left as typed. In doubt the scan does not substitute.
/// - The ":" that opens a token does not follow a letter or a digit, so
///   "a:b:c" stays text.
/// - The URL and the name are HTML-attribute-escaped.
///
/// Usage:
/// ```swift
/// let markdown = ComposerEmojiMarkup.resolving(markdown: "hi :parrot:", packs: packs)
/// ```
public enum ComposerEmojiMarkup {
    // MARK: - Lookup

    /// The image URL of each shortcode. A shortcode that two packs have
    /// keeps the image of the first pack. An emoji that the tag cannot hold
    /// safely is left out: a URL that is not `mxc://`, or a URL or a name
    /// with whitespace, a backtick, a backslash, or a colon in the name.
    public static func shortcodeURLs(in packs: [ImagePack]) -> [String: String] {
        var urls: [String: String] = [:]
        for pack in packs {
            for emoji in pack.emoji where urls[emoji.shortcode] == nil {
                guard ImagePack.isImageKey(emoji.url),
                      !emoji.shortcode.isEmpty,
                      !emoji.shortcode.contains(where: { $0 == ":" || !isTagSafe($0) }),
                      !emoji.url.contains(where: { !isTagSafe($0) })
                else { continue }
                urls[emoji.shortcode] = emoji.url
            }
        }
        return urls
    }

    private static func isTagSafe(_ character: Character) -> Bool {
        !character.isWhitespace && character != "`" && character != "\\"
            && !character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    // MARK: - Tag

    /// The emoticon tag for one emoji.
    ///
    /// - Parameters:
    ///   - shortcode: the name without colons.
    ///   - url: the `mxc://` URL.
    ///   - aloneOnLine: true when the tag is the only content of its line. A
    ///     line with one complete tag and nothing else starts a markdown HTML
    ///     block, and the lines after it would lose their formatting. A line
    ///     break before the tag's end prevents that and is valid HTML.
    public static func tag(shortcode: String, url: String, aloneOnLine: Bool = false) -> String {
        let name = escapeAttribute(":" + shortcode + ":")
        let end = aloneOnLine ? "\n/>" : " />"
        return "<img data-mx-emoticon src=\"\(escapeAttribute(url))\" alt=\"\(name)\" title=\"\(name)\" height=\"32\"\(end)"
    }

    /// Escapes text for a double-quoted HTML attribute value.
    static func escapeAttribute(_ text: String) -> String {
        var result = ""
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "\"": result += "&quot;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }

    // MARK: - Substitution

    /// Whether a token can open after `character`. A ":" after a letter or a
    /// digit is text, so "a:b:c" stays text. The composer's emoji picker
    /// (MATRIX-234) puts a space before a token where this rule keeps the
    /// token as text.
    public static func tokenCanFollow(_ character: Character) -> Bool {
        !character.isLetter && !character.isNumber
    }

    /// The message markdown with each resolved `:name:` as an emoticon tag.
    ///
    /// - Parameters:
    ///   - markdown: the markdown for `messageEventContentFromMarkdown`.
    ///   - packs: the image packs of the room the message goes to.
    /// - Returns: the markdown to send. The input itself when no token
    ///   resolves.
    public static func resolving(markdown: String, packs: [ImagePack]) -> String {
        guard !packs.isEmpty, markdown.contains(":") else { return markdown }
        return resolving(markdown: markdown, urls: shortcodeURLs(in: packs))
    }

    static func resolving(markdown: String, urls: [String: String]) -> String {
        guard !urls.isEmpty else { return markdown }
        var scanner = Scanner(characters: Array(markdown), urls: urls)
        scanner.run()
        return scanner.resolvedAny ? scanner.output : markdown
    }

    // MARK: - Sent body back to draft text

    /// The text of a sent body with each emoticon tag of this type as its
    /// `:name:` token again.
    ///
    /// The SDK's markdown call puts the markdown source into the plain
    /// `body`, so the body of a message with a resolved emoji holds the tag.
    /// Every reader of the plain body that shows or copies it goes through
    /// this function (`displayBody` in `Core`). Only a tag of the exact form
    /// that `tag` writes is mapped; other HTML in a body stays as typed.
    ///
    /// - Parameter body: the plain body of a message.
    public static func draftText(fromBody body: String) -> String {
        guard body.contains("<img data-mx-emoticon "), let sentTag else { return body }
        let source = body as NSString
        var result = ""
        var location = 0
        for match in sentTag.matches(in: body, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: location, length: match.range.location - location))
            result += unescapeAttribute(source.substring(with: match.range(at: 1)))
            location = NSMaxRange(match.range)
        }
        return result + source.substring(from: location)
    }

    /// Nil only if the literal pattern did not compile; the body then stays
    /// as it is.
    private static let sentTag = try? NSRegularExpression(
        pattern: "<img data-mx-emoticon src=\"mxc://[^\"]*\" alt=\"(:[^\"]*:)\" title=\"[^\"]*\" height=\"32\"\\s*/>"
    )

    static func unescapeAttribute(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - Scanner

private extension ComposerEmojiMarkup {
    /// One pass over the markdown. It copies the text to `output` and
    /// replaces the resolved tokens. It knows only as much markdown as it
    /// needs to leave code, links, and HTML alone.
    struct Scanner {
        let characters: [Character]
        let urls: [String: String]
        let longestShortcode: Int

        var output = ""
        var resolvedAny = false
        private var index = 0
        /// The open fenced code block: its fence character and length.
        private var fence: (character: Character, length: Int)?
        /// Whether the current line has content before `index` other than
        /// indentation and block markers (quote, list).
        private var lineHasContent = false

        /// Characters that can stand before the content of a line: the
        /// indentation, a quote marker, and a list marker.
        private static let blockMarkers: Set<Character> = [
            " ", "\t", ">", "-", "+", "*", ".", ")", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
        ]

        init(characters: [Character], urls: [String: String]) {
            self.characters = characters
            self.urls = urls
            self.longestShortcode = urls.keys.map(\.count).max() ?? 0
        }

        mutating func run() {
            var atLineStart = true
            while index < characters.count {
                if atLineStart {
                    atLineStart = false
                    lineHasContent = false
                    if copyCodeLine() {
                        atLineStart = true
                        continue
                    }
                }
                let character = characters[index]
                if character.isNewline {
                    copy(through: index)
                    atLineStart = true
                    continue
                }
                step(character)
            }
        }

        /// Handles the character at `index`, which is not a line break.
        private mutating func step(_ character: Character) {
            switch character {
            case "\\":
                let next = index + 1
                copy(through: next < characters.count && !characters[next].isNewline ? next : index)
            case "`":
                copyCodeSpan()
            case "<":
                copy(through: htmlEnd() ?? index)
            case "]":
                copy(through: linkDestinationEnd() ?? index)
            case ":":
                if !substituteToken() { copy(through: index) }
            default:
                if !Self.blockMarkers.contains(character) { lineHasContent = true }
                output.append(character)
                index += 1
                return
            }
            lineHasContent = true
        }

        /// Copies `index...end` as it is.
        private mutating func copy(through end: Int) {
            output.append(contentsOf: characters[index ... end])
            index = end + 1
        }

        private func lineEnd(from start: Int) -> Int {
            var end = start
            while end < characters.count, !characters[end].isNewline {
                end += 1
            }
            return end
        }

        // MARK: Code blocks

        /// At a line start: copies the line if it is code (in a fenced
        /// block, a fence, or indented by four spaces or a tab).
        ///
        /// - Returns: true if it copied the line and its line break.
        private mutating func copyCodeLine() -> Bool {
            let end = lineEnd(from: index)
            let line = characters[index ..< end]
            let isCode: Bool
            if let open = fence {
                if let run = Self.fenceRun(in: line), run.character == open.character, run.length >= open.length, run.restIsBlank {
                    fence = nil
                }
                isCode = true
            } else if let run = Self.fenceRun(in: line), run.character == "~" || !run.restHasBacktick {
                fence = (run.character, run.length)
                isCode = true
            } else {
                isCode = Self.isIndentedCode(line)
            }
            guard isCode else { return false }
            copy(through: min(end, characters.count - 1))
            return true
        }

        /// The fence at the start of a line, after indentation and quote
        /// markers: three or more backticks or tildes.
        private static func fenceRun(in line: ArraySlice<Character>) -> FenceRun? {
            let content = line.drop { $0 == " " || $0 == ">" }
            guard let first = content.first, first == "`" || first == "~" else { return nil }
            let run = content.prefix { $0 == first }
            guard run.count >= 3 else { return nil }
            let rest = content.dropFirst(run.count)
            return FenceRun(
                character: first,
                length: run.count,
                restIsBlank: rest.allSatisfy(\.isWhitespace),
                restHasBacktick: rest.contains("`")
            )
        }

        private static func isIndentedCode(_ line: ArraySlice<Character>) -> Bool {
            guard line.contains(where: { !$0.isWhitespace }) else { return false }
            return line.first == "\t" || (line.count >= 4 && line.prefix(4).allSatisfy { $0 == " " })
        }

        // MARK: Inline spans

        /// At a backtick run: copies a code span through its closing run of
        /// the same length, or only the run if the span does not close in
        /// the paragraph.
        private mutating func copyCodeSpan() {
            var runEnd = index
            while runEnd < characters.count, characters[runEnd] == "`" {
                runEnd += 1
            }
            let length = runEnd - index
            var cursor = runEnd
            while cursor < characters.count {
                let character = characters[cursor]
                if character.isNewline, cursor + 1 < characters.count, characters[cursor + 1].isNewline { break }
                guard character == "`" else {
                    cursor += 1
                    continue
                }
                var closeEnd = cursor
                while closeEnd < characters.count, characters[closeEnd] == "`" {
                    closeEnd += 1
                }
                if closeEnd - cursor == length {
                    copy(through: closeEnd - 1)
                    return
                }
                cursor = closeEnd
            }
            copy(through: runEnd - 1)
        }

        /// At "<": the index of the ">" that ends an autolink or an HTML tag
        /// on this line, or nil if the "<" is text.
        private func htmlEnd() -> Int? {
            let next = index + 1
            guard next < characters.count else { return nil }
            let start = characters[next]
            guard start.isLetter || start == "/" || start == "!" || start == "?" else { return nil }
            let end = lineEnd(from: next)
            return characters[next ..< end].firstIndex(of: ">")
        }

        /// At "]": the index of the ")" that ends a link destination on this
        /// line, or nil if no "(" follows.
        private func linkDestinationEnd() -> Int? {
            let open = index + 1
            guard open < characters.count, characters[open] == "(" else { return nil }
            var depth = 0
            var cursor = open
            let end = lineEnd(from: open)
            while cursor < end {
                switch characters[cursor] {
                case "\\": cursor += 1
                case "(": depth += 1
                case ")":
                    depth -= 1
                    if depth == 0 { return cursor }
                default: break
                }
                cursor += 1
            }
            return nil
        }

        // MARK: Token

        /// At ":": writes the tag if a pack shortcode and a closing ":"
        /// follow.
        ///
        /// - Returns: false if the ":" is text.
        private mutating func substituteToken() -> Bool {
            if index > 0, !ComposerEmojiMarkup.tokenCanFollow(characters[index - 1]) { return false }
            var close = index + 1
            while close < characters.count, close - index - 1 <= longestShortcode {
                let character = characters[close]
                if character == ":" { break }
                if character.isWhitespace || character == "`" || character == "\\" { return false }
                close += 1
            }
            guard close < characters.count, characters[close] == ":", close > index + 1 else { return false }
            let shortcode = String(characters[index + 1 ..< close])
            guard let url = urls[shortcode] else { return false }

            let restOfLine = characters[(close + 1) ..< lineEnd(from: close + 1)]
            let aloneOnLine = !lineHasContent && restOfLine.allSatisfy(\.isWhitespace)
            output += ComposerEmojiMarkup.tag(shortcode: shortcode, url: url, aloneOnLine: aloneOnLine)
            index = close + 1
            resolvedAny = true
            return true
        }
    }
}

/// A run of three or more backticks or tildes at the start of a line.
private struct FenceRun {
    let character: Character
    let length: Int
    /// Only whitespace follows the run: it can close a block.
    let restIsBlank: Bool
    /// A backtick follows the run: a backtick run is then not a fence.
    let restHasBacktick: Bool
}

// MARK: - Outgoing content

public extension ComposerOutgoingMessage {
    /// The message with its `:name:` tokens resolved against the image packs
    /// of the room it goes to. The same value when no token resolves.
    func resolvingEmoji(in packs: [ImagePack]) -> ComposerOutgoingMessage {
        ComposerOutgoingMessage(
            markdown: ComposerEmojiMarkup.resolving(markdown: markdown, packs: packs),
            mentionedUserIds: mentionedUserIds
        )
    }
}

public extension ComposerEditContent {
    /// The edit with the `:name:` tokens of a text message resolved. A
    /// caption goes as plain text and stays as it is.
    func resolvingEmoji(in packs: [ImagePack]) -> ComposerEditContent {
        switch self {
        case let .message(outgoing):
            .message(outgoing.resolvingEmoji(in: packs))
        case .caption:
            self
        }
    }
}
