import Foundation

// MATRIX-212: the registry of the account's scheduled messages, kept in
// global account data.
//
// The server holds each scheduled message (MSC4140, `Room.sendDelayedEvent`)
// and the FFI cannot list them, so the app keeps its own list. Account data
// is not encrypted on the server, so an entry holds the delay ID, the room
// ID, and the due time. Never the message text: the Mac that scheduled a
// message keeps its text in a local file (`ScheduledMessagePreviewStore`).

/// One scheduled message (MATRIX-212).
public struct ScheduledMessage: Equatable, Sendable, Identifiable {
    /// The server's `delay_id`. Send Now and Cancel use it.
    public var delayId: String
    /// The room the message goes to. In a merged chat, the member room.
    public var roomId: String
    /// The time the server sends the message. The server can send up to
    /// 30 seconds later (MSC4140).
    public var sendAt: Date
    /// Fields of this entry that this build does not know, written back
    /// unchanged.
    var unknownFields: [String: JSONValue]

    public var id: String { delayId }

    public init(delayId: String, roomId: String, sendAt: Date) {
        self.init(delayId: delayId, roomId: roomId, sendAt: sendAt, unknownFields: [:])
    }

    init(delayId: String, roomId: String, sendAt: Date, unknownFields: [String: JSONValue]) {
        self.delayId = delayId
        self.roomId = roomId
        // The wire keeps milliseconds. Round now, so a written document
        // equals its sync echo (`AccountDataEchoGate`).
        self.sendAt = Self.wireDate(Self.wireMilliseconds(sendAt))
        self.unknownFields = unknownFields
    }

    static func wireMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func wireDate(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}

/// The account's scheduled messages (MATRIX-212).
///
/// Stored in global account data under `ScheduledMessageDocument.eventType`:
///
/// ```json
/// {"version": 1, "messages": [
///   {"delay_id": "abc", "room_id": "!a:davlin.io", "send_at": 1800000000000}]}
/// ```
///
/// `send_at` is milliseconds since the Unix epoch, as Matrix timestamps
/// are. Fields this build does not know survive a read-modify-write, at the
/// top level and in each entry. A delay ID is in the list at most once.
public struct ScheduledMessageDocument: Equatable, Sendable {
    /// The global account-data event type (contract §11, 2026-11-23).
    public static let eventType = "io.davlin.matrixclient.scheduled"

    /// The schema version this build writes.
    public static let currentVersion = 1

    /// How long after its due time an entry stays. MSC4140 lets the server
    /// send up to 30 seconds late.
    public static let sendGrace: TimeInterval = 30

    public var version: Int
    /// The entries in stored order: each new one is appended.
    public private(set) var messages: [ScheduledMessage]
    /// Top-level fields this build does not know.
    var unknownFields: [String: JSONValue]

    public init(version: Int = ScheduledMessageDocument.currentVersion, messages: [ScheduledMessage] = []) {
        self.init(version: version, messages: messages, unknownFields: [:])
    }

    init(version: Int, messages: [ScheduledMessage], unknownFields: [String: JSONValue]) {
        self.version = version
        var seen = Set<String>()
        // A delay ID twice keeps its first entry.
        self.messages = messages.filter { seen.insert($0.delayId).inserted }
        self.unknownFields = unknownFields
    }

    /// This build may write the document. A newer schema is read but never
    /// overwritten.
    public var isWritable: Bool {
        version <= Self.currentVersion
    }

    /// The rooms with at least one scheduled message.
    public var roomIds: Set<String> {
        Set(messages.map(\.roomId))
    }

    /// The scheduled messages of `roomIds`, the earliest due first.
    public func messages(inRooms roomIds: Set<String>) -> [ScheduledMessage] {
        messages
            .filter { roomIds.contains($0.roomId) }
            .sorted { $0.sendAt != $1.sendAt ? $0.sendAt < $1.sendAt : $0.delayId < $1.delayId }
    }

    public func message(delayId: String) -> ScheduledMessage? {
        messages.first { $0.delayId == delayId }
    }

    /// Adds `message`. A delay ID that is already in the list keeps its
    /// first entry.
    public mutating func add(_ message: ScheduledMessage) {
        guard self.message(delayId: message.delayId) == nil else { return }
        messages.append(message)
    }

    /// Removes the entries of `delayIds`.
    public mutating func remove(delayIds: Set<String>) {
        messages.removeAll { delayIds.contains($0.delayId) }
    }

    /// The entries the server has sent at `now`: their due time plus
    /// `sendGrace` has passed.
    public func sentMessages(at now: Date) -> [ScheduledMessage] {
        messages.filter { $0.sendAt.addingTimeInterval(Self.sendGrace) <= now }
    }

    /// When the next entry leaves the list, or nil when the list is empty.
    public var nextCleanupDate: Date? {
        messages.map { $0.sendAt.addingTimeInterval(Self.sendGrace) }.min()
    }
}

// MARK: - Codable

private enum ScheduledMessageKeyName {
    static let version = "version"
    static let messages = "messages"
    static let delayId = "delay_id"
    static let roomId = "room_id"
    static let sendAt = "send_at"

    static let documentKeys: Set<String> = [version, messages]
    static let entryKeys: Set<String> = [delayId, roomId, sendAt]
}

extension ScheduledMessage: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let milliseconds = try container.decode(Int64.self, forKey: AnyCodingKey(ScheduledMessageKeyName.sendAt))
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !ScheduledMessageKeyName.entryKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        try self.init(
            delayId: container.decode(String.self, forKey: AnyCodingKey(ScheduledMessageKeyName.delayId)),
            roomId: container.decode(String.self, forKey: AnyCodingKey(ScheduledMessageKeyName.roomId)),
            sendAt: Self.wireDate(milliseconds),
            unknownFields: unknown
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(delayId, forKey: AnyCodingKey(ScheduledMessageKeyName.delayId))
        try container.encode(roomId, forKey: AnyCodingKey(ScheduledMessageKeyName.roomId))
        try container.encode(Self.wireMilliseconds(sendAt), forKey: AnyCodingKey(ScheduledMessageKeyName.sendAt))
    }
}

extension ScheduledMessageDocument: Codable {
    /// A missing `version` reads as version 1, a missing `messages` as no
    /// messages. An entry without its fields fails the decode: the app then
    /// refuses every write, so it cannot drop entries it could not read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let version = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey(ScheduledMessageKeyName.version))
            ?? Self.currentVersion
        let messages = try container.decodeIfPresent(
            [ScheduledMessage].self,
            forKey: AnyCodingKey(ScheduledMessageKeyName.messages)
        ) ?? []
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !ScheduledMessageKeyName.documentKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.init(version: version, messages: messages, unknownFields: unknown)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(version, forKey: AnyCodingKey(ScheduledMessageKeyName.version))
        try container.encode(messages, forKey: AnyCodingKey(ScheduledMessageKeyName.messages))
    }
}

// MARK: - Reading and writing

/// The result of reading the scheduled-messages account data (MATRIX-212).
public enum ScheduledMessageReadResult: Equatable, Sendable {
    /// The account has no event yet. Writes start from an empty document.
    case empty
    case parsed(ScheduledMessageDocument)
    /// The event exists but did not parse. The app shows no scheduled
    /// messages and refuses every write.
    case unreadable(raw: String, reason: String)

    /// The scheduled messages to show.
    public var document: ScheduledMessageDocument {
        switch self {
        case .empty, .unreadable: ScheduledMessageDocument()
        case let .parsed(document): document
        }
    }

    /// The document a change may start from, or nil when writing is unsafe:
    /// the event is unreadable or has a newer `version`.
    public var writableBase: ScheduledMessageDocument? {
        switch self {
        case .empty: ScheduledMessageDocument()
        case let .parsed(document): document.isWritable ? document : nil
        case .unreadable: nil
        }
    }
}

public extension ScheduledMessageDocument {
    /// Parses the account data content. `json` is nil when the event is
    /// unset.
    static func read(_ json: String?) -> ScheduledMessageReadResult {
        guard let json else { return .empty }
        do {
            return try .parsed(JSONDecoder().decode(ScheduledMessageDocument.self, from: Data(json.utf8)))
        } catch {
            return .unreadable(raw: json, reason: String(describing: error))
        }
    }

    /// The content to write. Keys are sorted so equal documents encode to
    /// the same string.
    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "JSONEncoder produced non-UTF-8 output"))
        }
        return json
    }
}
