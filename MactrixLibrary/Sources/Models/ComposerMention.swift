import Foundation

/// A user the composer mentions (MATRIX-105, decision D-6).
///
/// The composer shows a mention as one atomic chip. On send the chip becomes a
/// `matrix.to` pill link in the markdown, and the user id goes into the
/// content's `m.mentions`.
public struct MentionTarget: Hashable, Sendable {
    /// The full Matrix user id, for example `@alice:example.org`.
    public let userId: String
    /// The name the chip shows and the pill link text. Can be empty; see
    /// `label`.
    public let displayName: String

    public init(userId: String, displayName: String?) {
        self.userId = userId
        self.displayName = displayName ?? ""
    }

    /// The text for the chip and the pill link: the display name on one line,
    /// or the user id when the display name is empty.
    public var label: String {
        let oneLine = displayName
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return oneLine.isEmpty ? userId : oneLine
    }
}

/// One piece of composer content: plain text the user typed, or a mention
/// chip.
public enum ComposerSegment: Equatable, Sendable {
    case text(String)
    case mention(MentionTarget)
}

/// The message the composer sends: the markdown to give to
/// `messageEventContentFromMarkdown`, and the user ids for `m.mentions`.
public struct ComposerOutgoingMessage: Equatable, Sendable {
    public let markdown: String
    /// Unique, in the order of first appearance. Empty when the message has
    /// no mention chip.
    public let mentionedUserIds: [String]
}

/// Converts composer content between mention chips and markdown pill links.
///
/// There are two text forms:
///
/// - **Draft text** (`draftText(for:)`): text segments as typed, and each chip
///   as `[label](https://matrix.to/#/@user:server)` with the label escaped.
///   `segments(fromDraftText:)` inverts it exactly. The composer binding and
///   the saved `ComposerDraft.plainText` use this form, so a draft keeps its
///   chips.
/// - **Message markdown** (`outgoingMessage(fromDraftText:)`): the draft text
///   plus escapes where typed text touches a pill, so that markdown cannot
///   join the two. For example, `hey!` before a pill would make `![` and turn
///   the link into an image.
///
/// Pure logic with no SDK or UI types, so it is unit-tested in `ModelsTests`.
public enum MentionMarkdown {
    /// The permalink prefix for a pill. A user id follows it.
    public static let permalinkPrefix = "https://matrix.to/#/"

    /// The ASCII punctuation that the link text escapes. These are the
    /// characters that can start inline markdown, end the link text, or start
    /// an HTML entity.
    static let linkTextSpecialCharacters: Set<Character> = ["\\", "`", "*", "_", "[", "]", "<", ">", "~", "&"]

    // MARK: - Chips to text

    /// The draft text for some segments. See the type documentation.
    ///
    /// - Parameter segments: the composer content.
    /// - Returns: text segments unchanged, each chip as a pill link.
    public static func draftText(for segments: [ComposerSegment]) -> String {
        segments.reduce(into: "") { result, segment in
            switch segment {
            case let .text(text):
                result += text
            case let .mention(target):
                result += pill(for: target)
            }
        }
    }

    /// The markdown to send for some segments. The same as `draftText(for:)`,
    /// plus boundary escapes before each pill.
    ///
    /// - Parameter segments: the composer content.
    /// - Returns: the markdown for `messageEventContentFromMarkdown`.
    public static func messageMarkdown(for segments: [ComposerSegment]) -> String {
        segments.reduce(into: "") { result, segment in
            switch segment {
            case let .text(text):
                result += text
            case let .mention(target):
                escapeBoundary(before: &result)
                result += pill(for: target)
            }
        }
    }

    /// The text to put on the pasteboard for other apps: each chip as
    /// `@label`.
    ///
    /// - Parameter segments: the composer content.
    /// - Returns: plain text with no markdown links.
    public static func plainText(for segments: [ComposerSegment]) -> String {
        segments.reduce(into: "") { result, segment in
            switch segment {
            case let .text(text):
                result += text
            case let .mention(target):
                result += "@" + target.label
            }
        }
    }

    /// The user ids that the chips mention, for `Mentions.userIds`.
    ///
    /// - Parameter segments: the composer content.
    /// - Returns: each id one time, in the order of first appearance.
    public static func mentionedUserIds(in segments: [ComposerSegment]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for case let .mention(target) in segments where seen.insert(target.userId).inserted {
            result.append(target.userId)
        }
        return result
    }

    /// The message for a draft text: the markdown and the mention set.
    ///
    /// - Parameter draftText: the composer binding value.
    /// - Returns: what `ChatInputView` sends.
    public static func outgoingMessage(fromDraftText draftText: String) -> ComposerOutgoingMessage {
        let segments = segments(fromDraftText: draftText)
        return ComposerOutgoingMessage(
            markdown: messageMarkdown(for: segments),
            mentionedUserIds: mentionedUserIds(in: segments)
        )
    }

    /// The pill link for one chip.
    static func pill(for target: MentionTarget) -> String {
        "[" + escapeLinkText(target.label) + "](" + permalink(for: target.userId) + ")"
    }

    /// The `matrix.to` permalink for a user id. Parentheses and characters
    /// that a URL fragment cannot hold are percent-encoded, so the link
    /// destination always ends at the closing parenthesis.
    static func permalink(for userId: String) -> String {
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "()")
        return permalinkPrefix + (userId.addingPercentEncoding(withAllowedCharacters: allowed) ?? userId)
    }

    /// Backslash-escapes the markdown characters in a pill label.
    static func escapeLinkText(_ text: String) -> String {
        var result = ""
        for character in text {
            if linkTextSpecialCharacters.contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }

    /// Adds an escape to the end of `markdown` if its last character would
    /// join the pill that follows:
    ///
    /// - An odd run of backslashes would escape the pill's `[`. One more
    ///   backslash makes the run even.
    /// - An unescaped `!` would make `![`, an image. It becomes `\!`.
    static func escapeBoundary(before markdown: inout String) {
        let trailingBackslashes = markdown.reversed().prefix { $0 == "\\" }.count
        if trailingBackslashes % 2 == 1 {
            markdown.append("\\")
            return
        }
        guard markdown.last == "!" else { return }
        let backslashesBeforeBang = markdown.dropLast().reversed().prefix { $0 == "\\" }.count
        if backslashesBeforeBang % 2 == 0 {
            markdown.insert("\\", at: markdown.index(before: markdown.endIndex))
        }
    }

    // MARK: - Text to chips

    /// The segments for a draft text: each well-formed user pill becomes a
    /// chip, and all other text stays text.
    ///
    /// A pill is `[label](https://matrix.to/#/@localpart:server)` on one
    /// line. Links to rooms or events, and malformed links, stay text.
    ///
    /// - Parameter text: a draft text, or any typed text.
    /// - Returns: the segments, with no two text segments next to each other.
    public static func segments(fromDraftText text: String) -> [ComposerSegment] {
        var segments: [ComposerSegment] = []
        var pendingText = ""
        var index = text.startIndex

        while index < text.endIndex {
            if text[index] == "[", let (target, end) = parsePill(in: text, at: index) {
                if !pendingText.isEmpty {
                    segments.append(.text(pendingText))
                    pendingText = ""
                }
                segments.append(.mention(target))
                index = end
            } else {
                pendingText.append(text[index])
                index = text.index(after: index)
            }
        }
        if !pendingText.isEmpty {
            segments.append(.text(pendingText))
        }
        return segments
    }

    /// Parses one pill that starts at `start` (an `[`).
    ///
    /// - Returns: the chip and the index after the closing `)`, or nil if the
    ///   text at `start` is not a user pill.
    static func parsePill(in text: String, at start: String.Index) -> (MentionTarget, String.Index)? {
        // Link text: up to the first unescaped "]", on one line.
        var escapedLabel = ""
        var index = text.index(after: start)
        var closed = false
        while index < text.endIndex {
            let character = text[index]
            if character.isNewline { return nil }
            if character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else { return nil }
                escapedLabel.append(character)
                escapedLabel.append(text[next])
                index = text.index(after: next)
                continue
            }
            if character == "]" {
                closed = true
                index = text.index(after: index)
                break
            }
            escapedLabel.append(character)
            index = text.index(after: index)
        }
        guard closed, !escapedLabel.isEmpty else { return nil }

        // Destination: "(" + permalink prefix + user id + ")".
        let opening = "(" + permalinkPrefix
        guard text[index...].hasPrefix(opening) else { return nil }
        let idStart = text.index(index, offsetBy: opening.count)
        guard let close = text[idStart...].firstIndex(of: ")") else { return nil }
        let rawUserId = text[idStart ..< close]
        guard !rawUserId.contains(where: \.isWhitespace) else { return nil }
        let userId = rawUserId.removingPercentEncoding ?? String(rawUserId)
        guard isUserId(userId) else { return nil }

        let target = MentionTarget(userId: userId, displayName: unescapeLinkText(escapedLabel))
        return (target, text.index(after: close))
    }

    /// Removes the backslash before each escaped ASCII punctuation character.
    static func unescapeLinkText(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if character == "\\", next < text.endIndex, text[next].isASCII, text[next].isPunctuation || text[next].isSymbol {
                result.append(text[next])
                index = text.index(after: next)
            } else {
                result.append(character)
                index = next
            }
        }
        return result
    }

    /// Whether a string has the shape of a Matrix user id: `@`, a localpart,
    /// `:`, and a server name. This is a shape check only, not validation.
    static func isUserId(_ candidate: String) -> Bool {
        guard candidate.hasPrefix("@"), let colon = candidate.firstIndex(of: ":") else { return false }
        let localpart = candidate[candidate.index(after: candidate.startIndex) ..< colon]
        let server = candidate[candidate.index(after: colon)...]
        return !localpart.isEmpty && !server.isEmpty
    }
}
