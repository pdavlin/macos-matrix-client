import Foundation

// MATRIX-212: the rules of Send Later that need no SDK: the event content,
// the plain text, the errors, the local text store, and the chat-list mark.

/// The `m.room.message` content that Send Later gives to
/// `Room.sendDelayedEvent` (MATRIX-212).
///
/// Plain text only (contract §11, 2026-11-23): the FFI cannot turn the
/// composer's content into JSON and has no markdown-to-HTML call. So the
/// content is `msgtype` and `body` and nothing else: no `format`, no
/// `formatted_body`, no `m.mentions`, no `m.relates_to`. Making those here
/// would be protocol logic outside the SDK (hard rule 1).
public struct ScheduledMessageContent: Codable, Equatable, Sendable {
    /// The event type of a scheduled message.
    public static let eventType = "m.room.message"

    public let msgtype: String
    public let body: String

    public init(body: String) {
        msgtype = "m.text"
        self.body = body
    }

    /// The content as a JSON string, from `JSONEncoder`.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "JSONEncoder produced non-UTF-8 output"))
        }
        return json
    }
}

/// The text Send Later sends for the composer's draft text (MATRIX-212).
public struct ScheduledMessageText: Equatable, Sendable {
    /// The plain-text body: typed text, and each mention chip as "@name".
    public let body: String
    /// The draft has a mention chip, which will not notify.
    public let hasMention: Bool
    /// The draft has markdown that the normal send would format.
    public let hasFormatting: Bool

    /// The sheet shows the plain-text note.
    public var losesFormatting: Bool {
        hasMention || hasFormatting
    }

    /// The note the sheet shows when `losesFormatting`.
    public static let plainTextNote = "Sends as plain text. Mentions do not notify, and formatting is removed."

    /// - Parameters:
    ///   - draftText: the composer binding value (chips as pill links).
    ///   - hasCustomEmoji: the normal send would turn a `:name:` into an
    ///     image (MATRIX-156). It counts as formatting.
    public init(draftText: String, hasCustomEmoji: Bool = false) {
        let segments = MentionMarkdown.segments(fromDraftText: draftText)
        body = MentionMarkdown.plainText(for: segments).trimmingCharacters(in: .whitespacesAndNewlines)
        hasMention = segments.contains {
            if case .mention = $0 { return true }
            return false
        }
        let typed = segments.reduce(into: "") { result, segment in
            if case let .text(text) = segment {
                result += text
            }
        }
        hasFormatting = hasCustomEmoji || Self.hasMarkdownFormatting(typed)
    }

    /// Whether `text` holds markdown that renders as formatting: emphasis,
    /// code, a link, a heading, a list, a quote, or a code block. Line
    /// breaks and plain paragraphs do not count. Foundation's markdown
    /// reader decides; it only feeds the note, never the content.
    static func hasMarkdownFormatting(_ text: String) -> Bool {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: text, options: options) else { return false }
        for run in parsed.runs {
            if run.link != nil || run.imageURL != nil {
                return true
            }
            if let inline = run.inlinePresentationIntent, !inline.subtracting([.softBreak, .lineBreak]).isEmpty {
                return true
            }
            if let block = run.presentationIntent, block.components.contains(where: { $0.kind != .paragraph }) {
                return true
            }
        }
        return false
    }
}

/// Why a Send Later action failed (MATRIX-212). The errors are in
/// docs/research/send-later.md §3.
public enum ScheduledMessageFailure: Error, Equatable, Sendable {
    /// `M_LIMIT_EXCEEDED`: the rate limit, or the per-user count limit
    /// (Synapse default 100).
    case rateLimited(retryAfter: TimeInterval?)
    /// `M_DELAY_TOO_LARGE`: the time is after the server's maximum delay.
    case delayTooLarge
    /// `M_FORBIDDEN`: the account cannot send in the room.
    case forbidden
    /// `M_NOT_FOUND` on an update: the message was sent or cancelled,
    /// maybe on another device.
    case notFound
    /// `M_UNRECOGNIZED`: the server has no MSC4140 endpoint.
    case unsupported
    /// The chosen time passed before the request.
    case timePassed
    /// The client does not know the room.
    case roomUnavailable
    /// The stored list is unreadable or from a newer build: no change is
    /// safe.
    case readOnly
    /// The account data write failed. The server's copy was cancelled.
    case registryWriteFailed
    /// Any other error, with its text.
    case other(String)

    /// The text for the alert.
    public var message: String {
        switch self {
        case let .rateLimited(retryAfter):
            let base = "The server limits how many messages you can schedule, and how fast."
            guard let retryAfter, retryAfter > 0 else { return "\(base) Try again later." }
            let seconds = Int(retryAfter.rounded(.up))
            return "\(base) Try again in \(seconds) \(seconds == 1 ? "second" : "seconds")."
        case .delayTooLarge:
            return "That time is too far ahead for the server. Pick an earlier time."
        case .forbidden:
            return "You do not have permission to send messages in this chat."
        case .notFound:
            return "This message was already sent or cancelled."
        case .unsupported:
            return "The server does not support scheduled messages."
        case .timePassed:
            return "That time has passed. Pick a later time."
        case .roomUnavailable:
            return "This chat is not available."
        case .readOnly:
            return "The list of scheduled messages is from a newer version of the app, so this version cannot change it."
        case .registryWriteFailed:
            return "The list of scheduled messages could not be saved, so the message was not scheduled."
        case let .other(detail):
            return "The server returned an error: \(detail)"
        }
    }

    /// The failure for an error code that the SDK reports as a custom kind.
    /// The stable and the unstable (MSC4140) code of a too-large delay both
    /// map to `delayTooLarge`.
    public static func custom(errcode: String, message: String) -> ScheduledMessageFailure {
        switch errcode {
        case "M_DELAY_TOO_LARGE", "ORG.MATRIX.MSC4140_DELAY_TOO_LARGE":
            .delayTooLarge
        default:
            .other(message.isEmpty ? errcode : message)
        }
    }
}

/// The local text of the scheduled messages this Mac made (MATRIX-212).
///
/// Account data is not encrypted on the server, so the text stays on the
/// Mac, in a JSON file in the session's data folder: each delay ID with its
/// text and due time. It is plain text at rest, as the search index is
/// (contract R-6). Sign-out removes the folder. Other devices show
/// "Scheduled message".
///
/// A text goes when this Mac drops its entry, or when its due time plus
/// `ScheduledMessageDocument.sendGrace` passes. It does not go when a read
/// of the registry lacks its entry: the SDK's store gets a write only from
/// the sync echo, so a read after a relaunch can be older than this Mac's
/// last write.
public struct ScheduledMessagePreviewStore: Sendable {
    /// The file, or nil for a store that is not saved (tests).
    let file: URL?
    private var entries: [String: ScheduledMessagePreviewEntry]

    /// Loads the file. A missing or unreadable file starts empty.
    public init(file: URL?) {
        self.file = file
        entries = file.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: ScheduledMessagePreviewEntry].self, from: $0) } ?? [:]
    }

    /// The text of each delay ID.
    public var texts: [String: String] {
        entries.mapValues(\.text)
    }

    /// Keeps `text` for `delayId` until `sendAt` has passed, and saves the
    /// file.
    public mutating func set(_ text: String, for delayId: String, sendAt: Date) {
        let entry = ScheduledMessagePreviewEntry(text: text, sendAt: ScheduledMessage.wireMilliseconds(sendAt))
        guard entries[delayId] != entry else { return }
        entries[delayId] = entry
        save()
    }

    /// Removes the text of `delayId`, and saves the file.
    public mutating func remove(_ delayId: String) {
        guard entries.removeValue(forKey: delayId) != nil else { return }
        save()
    }

    /// Removes the texts whose due time plus the grace has passed at `now`,
    /// and saves the file when one went.
    public mutating func removeExpired(at now: Date) {
        let limit = ScheduledMessage.wireMilliseconds(now.addingTimeInterval(-ScheduledMessageDocument.sendGrace))
        let kept = entries.filter { $0.value.sendAt > limit }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(entries).write(to: file, options: [.atomic])
        } catch {
            // The texts stay in memory. A failed save loses them at the
            // next launch only: the messages stay scheduled.
        }
    }
}

/// One text in `ScheduledMessagePreviewStore`'s file.
private struct ScheduledMessagePreviewEntry: Codable, Equatable, Sendable {
    var text: String
    /// Milliseconds since the Unix epoch.
    var sendAt: Int64

    enum CodingKeys: String, CodingKey {
        case text
        case sendAt = "send_at"
    }
}

/// A scheduled message and its local text (MATRIX-212).
public struct ScheduledMessageItem: Equatable, Sendable, Identifiable {
    public var message: ScheduledMessage
    /// The text, or nil when another device scheduled the message.
    public var text: String?

    public var id: String { message.delayId }

    public init(message: ScheduledMessage, text: String?) {
        self.message = message
        self.text = text
    }
}

/// The words of the Scheduled strip and list (MATRIX-212).
public enum ScheduledMessageStripText {
    /// "1 scheduled", "2 scheduled".
    public static func title(count: Int) -> String {
        "\(count) scheduled"
    }

    /// The row text of a message whose text this Mac does not have.
    public static let unknownText = "Scheduled message"
}

public extension VisibleChatList where Room == ChatListItem {
    /// The list with the clock mark on each chat that has a scheduled
    /// message (MATRIX-212). A merged chat has the mark when any member
    /// room has one.
    func withScheduledMarks(roomIds: Set<String>) -> VisibleChatList<ChatListItem> {
        guard !roomIds.isEmpty else { return self }
        func marked(_ item: ChatListItem) -> ChatListItem {
            guard item.roomIds.contains(where: roomIds.contains) else { return item }
            switch item {
            case var .room(entry):
                entry.row.hasScheduledMessages = true
                return .room(entry)
            case var .merged(merged):
                merged.row.hasScheduledMessages = true
                return .merged(merged)
            }
        }
        return VisibleChatList(favorites: favorites.map(marked), list: list.map(marked))
    }
}
