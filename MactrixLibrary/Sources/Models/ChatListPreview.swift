import Foundation

/// The latest event of a room, reduced to what a chat-list row shows
/// (MATRIX-67).
///
/// Platform-neutral on purpose: the app target maps the SDK's
/// `LatestEventValue` into this type, so the wording rules below are testable
/// without the SDK. The SDK picks which event is the latest one; this type only
/// describes it.
public struct ChatListLatestEvent: Equatable, Sendable {
    public var timestamp: Date
    public var sender: ChatListSender
    public var content: ChatListPreviewContent
    /// A local echo the send queue gave up on. The row shows a red error dot.
    public var hasSendFailure: Bool

    public init(
        timestamp: Date,
        sender: ChatListSender,
        content: ChatListPreviewContent,
        hasSendFailure: Bool = false
    ) {
        self.timestamp = timestamp
        self.sender = sender
        self.content = content
        self.hasSendFailure = hasSendFailure
    }
}

/// Who sent the latest event.
public struct ChatListSender: Equatable, Sendable {
    public var userId: String
    public var displayName: String?
    public var isOwn: Bool

    public init(userId: String, displayName: String?, isOwn: Bool) {
        self.userId = userId
        self.displayName = displayName
        self.isOwn = isOwn
    }

    /// The display name, or the user ID localpart when there is none.
    public var name: String {
        if let displayName, !displayName.isEmpty {
            return displayName
        }
        return Self.localpart(of: userId)
    }

    /// `@alice:example.org` → `alice`. Returns the input without its sigil
    /// when there is no server part.
    public static func localpart(of userId: String) -> String {
        let trimmed = userId.hasPrefix("@") ? userId.dropFirst() : Substring(userId)
        return String(trimmed.prefix { $0 != ":" })
    }
}

/// The kinds of latest event a row can describe.
public enum ChatListPreviewContent: Equatable, Sendable {
    /// Text, notice, or an unknown msgtype with a body.
    case text(String)
    case emote(String)
    case image
    case video
    case audio
    case file(name: String)
    case gallery
    case sticker
    case poll(question: String)
    case location
    case redacted
    case unableToDecrypt
    /// An invite to the room. The sender is the inviter, when known.
    case invite
    /// A membership change. The event's `sender` is the member whose
    /// membership changed, not the member who changed it.
    case membership(ChatListMembershipChange)
    /// Profile, state, call, and unparseable events. The row shows no preview.
    case other
}

/// The membership changes worth a preview line. Everything else maps to
/// `.other` and shows no preview.
public enum ChatListMembershipChange: Equatable, Sendable {
    case joined
    case left
    case invited
    case other
}

/// The preview line under the room title.
public struct ChatListPreview: Equatable, Sendable {
    public var text: String?
    public var hasSendFailure: Bool

    public init(text: String?, hasSendFailure: Bool) {
        self.text = text
        self.hasSendFailure = hasSendFailure
    }
}

public extension ChatListLatestEvent {
    /// The preview line for this event.
    ///
    /// Prefix rules: the account's own message reads "You: …"; another sender
    /// in a group room reads "Name: …"; the other person in a DM gets no
    /// prefix, because the row title already names them. Emotes, invites, and
    /// membership lines name the actor in the text itself and take no prefix.
    func preview(isDirect: Bool) -> ChatListPreview {
        ChatListPreview(text: previewText(isDirect: isDirect), hasSendFailure: hasSendFailure)
    }

    private func previewText(isDirect: Bool) -> String? {
        let body: String
        switch content {
        case let .text(text):
            guard let collapsed = Self.collapse(text) else { return nil }
            body = collapsed
        case let .emote(text):
            return "* \(sender.name) \(Self.collapse(text) ?? "")".trimmingCharacters(in: .whitespaces)
        case .image:
            body = "Photo"
        case .video:
            body = "Video"
        case .audio:
            body = "Audio"
        case let .file(name):
            body = Self.collapse(name) ?? "File"
        case .gallery:
            body = "Photos"
        case .sticker:
            body = "Sticker"
        case let .poll(question):
            body = "Poll: \(Self.collapse(question) ?? "")"
        case .location:
            body = "Location"
        case .redacted:
            body = "Message deleted"
        case .unableToDecrypt:
            body = "Encrypted message"
        case .invite:
            return "Invited you"
        case let .membership(change):
            return Self.membershipText(change, name: sender.name)
        case .other:
            return nil
        }

        if sender.isOwn {
            return "You: \(body)"
        }
        if !isDirect {
            return "\(sender.name): \(body)"
        }
        return body
    }

    private static func membershipText(_ change: ChatListMembershipChange, name: String) -> String? {
        switch change {
        case .joined:
            "\(name) joined"
        case .left:
            "\(name) left"
        case .invited:
            "\(name) was invited"
        case .other:
            nil
        }
    }

    /// Joins the lines of `text` with single spaces, so a multi-line message
    /// fills the two preview lines instead of breaking after the first.
    /// Returns nil for blank text.
    internal static func collapse(_ text: String) -> String? {
        let joined = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}
