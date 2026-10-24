import Foundation

/// Whether a label's chats also show in the Inbox (MATRIX-77).
///
/// Beeper's `inboxVisibility`. A value this build does not know decodes as
/// `.all`: showing a chat is the safe failure.
public enum ChatLabelInboxVisibility: String, Codable, Sendable {
    /// The label's chats show in the Inbox and in the label.
    case all
    /// The label's chats show only when the label is selected.
    case hidden
}

/// A user-defined group of chats, shown as an item in the sidebar's label
/// rail (MATRIX-77). A port of Beeper's labels.
///
/// Stored in the account's global account data (see `ChatLabelDocument`), so
/// every Mactrix window and device sees the same labels. Pure value type: the
/// app target reads and writes it through the SDK.
public struct ChatLabel: Identifiable, Equatable, Sendable {
    /// A UUID string, stable across renames.
    public var id: String
    public var name: String
    /// An index into the label palette (`LabelToken.palette`). Nil means the
    /// neutral color.
    public var colorIndex: Int?
    /// An SF Symbol name from the curated icon set. Nil means the label shows
    /// the first letter of its name.
    public var icon: String?
    /// A muted label silences its chats in Mactrix: see
    /// `ChatLabelDocument.labelMutedRoomIds`.
    public var isMuted: Bool
    public var inboxVisibility: ChatLabelInboxVisibility
    /// Room IDs, in the order the user added them. No duplicates.
    public var rooms: [String]
    /// Fields this build does not know, written back unchanged.
    var unknownFields: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        name: String,
        colorIndex: Int? = nil,
        icon: String? = nil,
        isMuted: Bool = false,
        inboxVisibility: ChatLabelInboxVisibility = .all,
        rooms: [String] = []
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.icon = icon
        self.isMuted = isMuted
        self.inboxVisibility = inboxVisibility
        self.rooms = rooms.uniqued()
        self.unknownFields = [:]
    }

    /// The label's chats show in the Inbox.
    public var isShownInInbox: Bool {
        inboxVisibility == .all
    }

    /// The text a label without an icon draws: the first letter of its name,
    /// upper-cased, or nothing for a blank name.
    public var monogram: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? ""
    }
}

extension ChatLabel: Codable {
    private static let knownKeys: Set<String> = ["id", "name", "colorIndex", "icon", "muted", "inboxVisibility", "rooms"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        id = try container.decode(String.self, forKey: AnyCodingKey("id"))
        name = try container.decode(String.self, forKey: AnyCodingKey("name"))
        colorIndex = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("colorIndex"))
        icon = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("icon"))
        isMuted = try container.decodeIfPresent(Bool.self, forKey: AnyCodingKey("muted")) ?? false
        let visibility = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("inboxVisibility"))
        inboxVisibility = visibility.flatMap(ChatLabelInboxVisibility.init(rawValue:)) ?? .all
        rooms = try (container.decodeIfPresent([String].self, forKey: AnyCodingKey("rooms")) ?? []).uniqued()

        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !Self.knownKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        unknownFields = unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(id, forKey: AnyCodingKey("id"))
        try container.encode(name, forKey: AnyCodingKey("name"))
        // Explicit nulls, matching Beeper's nullable fields.
        try container.encode(colorIndex, forKey: AnyCodingKey("colorIndex"))
        try container.encode(icon, forKey: AnyCodingKey("icon"))
        try container.encode(isMuted, forKey: AnyCodingKey("muted"))
        try container.encode(inboxVisibility, forKey: AnyCodingKey("inboxVisibility"))
        try container.encode(rooms, forKey: AnyCodingKey("rooms"))
    }
}

extension Array where Element: Hashable {
    /// The array without repeats, first occurrence kept.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
