import Foundation

// MATRIX-206: the JSON codec of the inbox-state account data. The wire
// format is in `InboxStateDocument`'s comment. Fields this build does not
// know are kept, at the top level and in each room entry, so a newer build's
// fields survive a write from this one.

private enum InboxStateKey {
    static let version = "version"
    static let rooms = "rooms"
    static let archivedAt = "archived_at"
    static let snoozedUntil = "snoozed_until"
    static let snoozedAt = "snoozed_at"
    static let remindAt = "remind_at"
    static let remindSetAt = "remind_set_at"

    static let documentKeys: Set<String> = [version, rooms]
    static let roomKeys: Set<String> = [archivedAt, snoozedUntil, snoozedAt, remindAt, remindSetAt]
}

/// One room entry on the wire: the known fields plus the ones this build
/// does not know.
private struct StoredInboxRoom: Codable {
    var state: InboxRoomState
    var unknownFields: [String: JSONValue]

    init(state: InboxRoomState, unknownFields: [String: JSONValue]) {
        self.state = state
        self.unknownFields = unknownFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        func date(_ key: String) throws -> Date? {
            try container.decodeIfPresent(Int64.self, forKey: AnyCodingKey(key)).map(Self.date(milliseconds:))
        }
        state = try InboxRoomState(
            archivedAt: date(InboxStateKey.archivedAt),
            snoozedUntil: date(InboxStateKey.snoozedUntil),
            snoozedAt: date(InboxStateKey.snoozedAt),
            remindAt: date(InboxStateKey.remindAt),
            remindSetAt: date(InboxStateKey.remindSetAt)
        )
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !InboxStateKey.roomKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        unknownFields = unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        func encode(_ date: Date?, _ key: String) throws {
            try container.encodeIfPresent(date.map(Self.milliseconds(of:)), forKey: AnyCodingKey(key))
        }
        try encode(state.archivedAt, InboxStateKey.archivedAt)
        try encode(state.snoozedUntil, InboxStateKey.snoozedUntil)
        try encode(state.snoozedAt, InboxStateKey.snoozedAt)
        try encode(state.remindAt, InboxStateKey.remindAt)
        try encode(state.remindSetAt, InboxStateKey.remindSetAt)
    }

    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    static func milliseconds(of date: Date) -> Int64 {
        InboxRoomState.milliseconds(of: date)
    }
}

extension InboxStateDocument: Codable {
    /// Decodes the account data content. A missing `version` reads as
    /// version 1, a missing `rooms` as no rooms.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let version = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey(InboxStateKey.version))
            ?? Self.currentVersion
        let stored = try container.decodeIfPresent([String: StoredInboxRoom].self, forKey: AnyCodingKey(InboxStateKey.rooms)) ?? [:]
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !InboxStateKey.documentKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.init(
            version: version,
            rooms: stored.mapValues(\.state),
            unknownFields: unknown,
            roomUnknownFields: stored.mapValues(\.unknownFields)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(version, forKey: AnyCodingKey(InboxStateKey.version))
        var stored: [String: StoredInboxRoom] = [:]
        for (roomId, state) in rooms {
            stored[roomId] = StoredInboxRoom(state: state, unknownFields: roomUnknownFields[roomId] ?? [:])
        }
        try container.encode(stored, forKey: AnyCodingKey(InboxStateKey.rooms))
    }

    /// The content to write. Keys are sorted so equal documents encode to
    /// the same string.
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, .init(codingPath: [], debugDescription: "JSONEncoder produced non-UTF-8 output"))
        }
        return json
    }

    /// Parses the account data content. `json` is nil when the event is
    /// unset.
    public static func read(_ json: String?) -> InboxStateReadResult {
        guard let json else { return .empty }
        do {
            return try .parsed(JSONDecoder().decode(InboxStateDocument.self, from: Data(json.utf8)))
        } catch {
            return .unreadable(raw: json, reason: String(describing: error))
        }
    }
}

/// The result of reading the inbox-state account data (MATRIX-206).
public enum InboxStateReadResult: Equatable, Sendable {
    /// The account has no inbox-state event yet. Writes start from an empty
    /// document.
    case empty
    /// The event parsed.
    case parsed(InboxStateDocument)
    /// The event exists but did not parse. Every chat shows in the Inbox
    /// and every write is refused, so a bug in this build cannot destroy
    /// data it could not read.
    case unreadable(raw: String, reason: String)

    /// The states to show: none when the event is missing or unreadable.
    public var document: InboxStateDocument {
        switch self {
        case .empty, .unreadable: InboxStateDocument()
        case let .parsed(document): document
        }
    }

    /// The document a mutation may start from, or nil when writing is
    /// unsafe: the event is unreadable or has a newer `version`.
    public var writableBase: InboxStateDocument? {
        switch self {
        case .empty: InboxStateDocument()
        case let .parsed(document): document.isWritable ? document : nil
        case .unreadable: nil
        }
    }
}

/// Decides whether a read of the inbox-state account data is current
/// (MATRIX-206). The same design as `MergedChatEchoGate`: after a write the
/// store holds the old event until sync brings the new one back, so the
/// gate keeps the written document until a read returns it or `timeout`
/// passes.
public struct InboxStateEchoGate: Sendable {
    public static let defaultTimeout: TimeInterval = 30

    private var pending: (document: InboxStateDocument, deadline: Date)?
    private let timeout: TimeInterval

    public init(timeout: TimeInterval = Self.defaultTimeout) {
        self.timeout = timeout
    }

    /// A write of `document` was sent at `now`.
    public mutating func didWrite(_ document: InboxStateDocument, now: Date = .now) {
        pending = (document, now.addingTimeInterval(timeout))
    }

    /// The document a write must start from while an echo is pending, or nil
    /// when the store is current.
    public mutating func pendingDocument(now: Date = .now) -> InboxStateDocument? {
        guard let pending else { return nil }
        if now >= pending.deadline {
            self.pending = nil
            return nil
        }
        return pending.document
    }

    /// Filters a read: the result to adopt, or nil to keep the written
    /// document because its echo has not arrived.
    public mutating func accept(_ read: InboxStateReadResult, now: Date = .now) -> InboxStateReadResult? {
        guard let pending else { return read }
        if case let .parsed(document) = read, document == pending.document {
            self.pending = nil
            return read
        }
        if now >= pending.deadline {
            self.pending = nil
            return read
        }
        return nil
    }
}
