import Foundation

/// The room and event of an APNs push from Sygnal (MATRIX-89).
///
/// The pusher uses the `event_id_only` format. Sygnal copies the pusher's
/// `default_payload` and adds `room_id` and `event_id` as top-level keys of
/// the APNs payload, so they arrive as top-level `userInfo` keys.
public struct PushNotificationPayload: Equatable, Sendable {
    public let roomID: String
    public let eventID: String

    public static let roomIDKey = "room_id"
    public static let eventIDKey = "event_id"

    public init(roomID: String, eventID: String) {
        self.roomID = roomID
        self.eventID = eventID
    }

    /// Returns `nil` if either identifier is missing, is not a string, or does
    /// not have the Matrix sigil (`!` for rooms, `$` for events).
    public init?(userInfo: [AnyHashable: Any]) {
        guard let roomID = Self.identifier(userInfo[Self.roomIDKey], sigil: "!"),
              let eventID = Self.identifier(userInfo[Self.eventIDKey], sigil: "$")
        else { return nil }
        self.init(roomID: roomID, eventID: eventID)
    }

    private static func identifier(_ value: Any?, sigil: Character) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 1, trimmed.first == sigil else { return nil }
        return trimmed
    }
}

/// The `default_payload` of the HTTP pusher (MATRIX-89).
///
/// `mutable-content` makes iOS run the Notification Service Extension. The
/// alert is the generic content that shows if the extension cannot decrypt
/// the event in time. The Sygnal config (MATRIX-90) must not override `aps`.
public enum PusherDefaultPayload {
    public static let json = #"{"aps":{"alert":{"body":"New message","title":"Mactrix"},"mutable-content":1}}"#
}

/// Encodes an APNs device token as the pusher `pushkey`.
public enum DeviceTokenEncoding {
    /// Lowercase hexadecimal, two digits for each byte. Sygnal's APNs pushkin
    /// expects this form.
    public static func hexString(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}

/// The SDK-free summary of a resolved notification event. Core maps the SDK's
/// `NotificationItem` to this value, so the display rules are testable without
/// SDK objects.
public struct NotificationSummary: Equatable, Sendable {
    public enum Body: Equatable, Sendable {
        case text(String)
        case image
        case video
        case audio
        case file
        case sticker
        case location
        case poll
        case encrypted
        case invite
        /// Any event that has no specific text, such as a call or a state event.
        case other
    }

    public let roomID: String
    public let roomDisplayName: String
    public let isDirect: Bool
    public let senderDisplayName: String
    public let body: Body
    /// `NotificationItem.isNoisy`. `nil` means unknown.
    public let isNoisy: Bool?

    public init(roomID: String, roomDisplayName: String, isDirect: Bool, senderDisplayName: String, body: Body, isNoisy: Bool?) {
        self.roomID = roomID
        self.roomDisplayName = roomDisplayName
        self.isDirect = isDirect
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.isNoisy = isNoisy
    }
}

/// The text of a notification banner.
public struct NotificationDisplay: Equatable, Sendable {
    public let title: String
    public let subtitle: String
    public let body: String
    /// Groups the notifications of one room.
    public let threadIdentifier: String
    public let playsSound: Bool

    /// The generic text if the event cannot be shown. Same text as the
    /// pusher's default payload.
    public static let fallbackTitle = "Mactrix"
    public static let fallbackBody = "New message"
    public static let encryptedBody = "Encrypted message"
    public static let inviteBody = "Invited you"

    public init(title: String, subtitle: String, body: String, threadIdentifier: String, playsSound: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadIdentifier = threadIdentifier
        self.playsSound = playsSound
    }

    /// A direct chat shows the sender as the title. A group room shows the room
    /// name as the title and the sender as the subtitle.
    public init(summary: NotificationSummary) {
        if summary.isDirect {
            title = summary.senderDisplayName
            subtitle = ""
        } else {
            title = summary.roomDisplayName
            subtitle = summary.senderDisplayName
        }
        body = Self.text(for: summary.body)
        threadIdentifier = summary.roomID
        playsSound = summary.isNoisy ?? true
    }

    static func text(for body: NotificationSummary.Body) -> String {
        switch body {
        case let .text(text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? fallbackBody : trimmed
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .file: return "File"
        case .sticker: return "Sticker"
        case .location: return "Location"
        case .poll: return "Poll"
        case .encrypted: return encryptedBody
        case .invite: return inviteBody
        case .other: return fallbackBody
        }
    }
}
