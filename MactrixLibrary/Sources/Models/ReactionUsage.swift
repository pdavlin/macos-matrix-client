import Foundation

// MATRIX-262: how often and when the account used each reaction key in each
// room, kept in global account data, so the Mac and the phone rank the quick
// reactions from the same record. `QuickReactionRanking` reads it.
//
// Account data is not encrypted on the server: the record holds room IDs,
// reaction keys, counts, and times. Never message text.

/// The uses of one reaction key in one room (MATRIX-262).
public struct ReactionUse: Equatable, Sendable {
    /// How many times the account added the reaction in the room.
    public var count: Int
    /// The last time the account added it.
    public var lastUsedAt: Date

    public init(count: Int, lastUsedAt: Date) {
        self.count = count
        self.lastUsedAt = lastUsedAt
    }

    /// Milliseconds since the Unix epoch, the unit of the wire format.
    static func milliseconds(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    /// The date of a wire value.
    static func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    /// `date` rounded to whole milliseconds, so a document equals itself
    /// after a round trip through the wire format (the echo gate compares
    /// the written document with the read one).
    static func wireDate(_ date: Date) -> Date {
        Self.date(milliseconds: milliseconds(of: date))
    }
}

/// The reaction keys the account used in one room (MATRIX-262).
public struct RoomReactionUsage: Equatable, Sendable {
    /// The uses by reaction key. A key is an emoji, or the `mxc://` URI of a
    /// custom emoji.
    public internal(set) var reactions: [String: ReactionUse]
    /// Fields of the room entry that this build does not know, written back
    /// unchanged.
    var unknownFields: [String: JSONValue]

    public init(reactions: [String: ReactionUse] = [:]) {
        self.init(reactions: reactions, unknownFields: [:])
    }

    init(reactions: [String: ReactionUse], unknownFields: [String: JSONValue]) {
        self.reactions = reactions
        self.unknownFields = unknownFields
    }

    /// The last use of any key in the room, or nil when the room has none.
    public var lastUsedAt: Date? {
        reactions.values.map(\.lastUsedAt).max()
    }

    /// The keys, the most used first. A tie goes to the most recent use,
    /// then to the key, so the order is stable.
    public var ranked: [String] {
        Self.ranked(reactions)
    }

    static func ranked(_ reactions: [String: ReactionUse]) -> [String] {
        reactions.sorted { lhs, rhs in
            if lhs.value.count != rhs.value.count {
                return lhs.value.count > rhs.value.count
            }
            if lhs.value.lastUsedAt != rhs.value.lastUsedAt {
                return lhs.value.lastUsedAt > rhs.value.lastUsedAt
            }
            return lhs.key < rhs.key
        }
        .map(\.key)
    }
}

/// The account's reaction use by room (MATRIX-262).
///
/// Stored in global account data under `eventType` (contract §11,
/// 2026-11-25):
///
///     {"version": 1, "rooms": {"!a:davlin.io": {"reactions": {
///       "👍": {"count": 4, "last_used_at": 1763500000000},
///       "mxc://davlin.io/abc": {"count": 1, "last_used_at": 1763400000000}}}}}
///
/// Times are milliseconds since the Unix epoch. Each use adds one to the
/// key's count; removing a reaction changes nothing. A room keeps at most
/// `maxReactionsPerRoom` keys and the document at most `maxRooms` rooms.
/// Fields this build does not know are kept, at the top level and in each
/// room entry, through a read-modify-write.
public struct ReactionUsageDocument: Equatable, Sendable {
    /// The global account-data event type.
    public static let eventType = "io.davlin.matrixclient.reaction_usage"

    /// The schema version this build writes.
    public static let currentVersion = 1

    /// The most keys one room keeps. A new key over the cap drops the key
    /// with the fewest uses, the oldest last use first.
    public static let maxReactionsPerRoom = 20

    /// The most rooms the document keeps. A new room over the cap drops the
    /// room with the oldest last use.
    public static let maxRooms = 300

    public var version: Int
    /// The rooms with a use. Never holds a room with no key.
    public private(set) var rooms: [String: RoomReactionUsage]
    /// Top-level fields this build does not know, written back unchanged.
    var unknownFields: [String: JSONValue]

    public init(version: Int = ReactionUsageDocument.currentVersion, rooms: [String: RoomReactionUsage] = [:]) {
        self.init(version: version, rooms: rooms, unknownFields: [:])
    }

    init(version: Int, rooms: [String: RoomReactionUsage], unknownFields: [String: JSONValue]) {
        self.version = version
        self.rooms = rooms.filter { !$0.value.reactions.isEmpty }
        self.unknownFields = unknownFields
    }

    /// This build may write the document. A newer schema is read but never
    /// overwritten.
    public var isWritable: Bool {
        version <= Self.currentVersion
    }

    /// Records one use of `key` in `roomId` at `date`: the count goes up by
    /// one, and the last use moves to `date` when that is later. Then the
    /// caps apply. They never drop the key or the room of this use.
    public mutating func record(_ key: String, inRoom roomId: String, at date: Date) {
        guard !key.isEmpty, !roomId.isEmpty else { return }
        let date = ReactionUse.wireDate(date)
        var room = rooms[roomId] ?? RoomReactionUsage()
        if var use = room.reactions[key] {
            use.count += 1
            use.lastUsedAt = max(use.lastUsedAt, date)
            room.reactions[key] = use
        } else {
            room.reactions[key] = ReactionUse(count: 1, lastUsedAt: date)
        }
        room.reactions = Self.capped(room.reactions, keeping: key)
        rooms[roomId] = room
        rooms = Self.capped(rooms, keeping: roomId)
    }

    /// The keys over `maxReactionsPerRoom` dropped: the fewest uses first,
    /// then the oldest last use. `key` stays.
    private static func capped(_ reactions: [String: ReactionUse], keeping key: String) -> [String: ReactionUse] {
        guard reactions.count > maxReactionsPerRoom else { return reactions }
        let kept = Set(RoomReactionUsage.ranked(reactions.filter { $0.key != key }).prefix(maxReactionsPerRoom - 1))
        return reactions.filter { $0.key == key || kept.contains($0.key) }
    }

    /// The rooms over `maxRooms` dropped: the oldest last use first.
    /// `roomId` stays.
    private static func capped(_ rooms: [String: RoomReactionUsage], keeping roomId: String) -> [String: RoomReactionUsage] {
        guard rooms.count > maxRooms else { return rooms }
        let lastUse: [String: Date] = rooms.mapValues { $0.lastUsedAt ?? .distantPast }
        let others: [String] = lastUse.keys.filter { $0 != roomId }
        let newestFirst = others.sorted { lhs, rhs in
            let left = lastUse[lhs] ?? .distantPast
            let right = lastUse[rhs] ?? .distantPast
            return left != right ? left > right : lhs < rhs
        }
        let keep = Set(newestFirst.prefix(maxRooms - 1)).union([roomId])
        return rooms.filter { keep.contains($0.key) }
    }
}

// MARK: - Codable

private enum ReactionUsageKey {
    static let version = "version"
    static let rooms = "rooms"
    static let reactions = "reactions"
    static let count = "count"
    static let lastUsedAt = "last_used_at"

    static let documentKeys: Set<String> = [version, rooms]
    static let roomKeys: Set<String> = [reactions]
}

extension ReactionUse: Codable {
    /// A use without its count or time fails the decode: the app then
    /// refuses every write, so it cannot drop data it could not read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        try self.init(
            count: container.decode(Int.self, forKey: AnyCodingKey(ReactionUsageKey.count)),
            lastUsedAt: Self.date(milliseconds: container.decode(Int64.self, forKey: AnyCodingKey(ReactionUsageKey.lastUsedAt)))
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        try container.encode(count, forKey: AnyCodingKey(ReactionUsageKey.count))
        try container.encode(Self.milliseconds(of: lastUsedAt), forKey: AnyCodingKey(ReactionUsageKey.lastUsedAt))
    }
}

extension RoomReactionUsage: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let reactions = try container.decodeIfPresent([String: ReactionUse].self, forKey: AnyCodingKey(ReactionUsageKey.reactions)) ?? [:]
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !ReactionUsageKey.roomKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.init(reactions: reactions, unknownFields: unknown)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(reactions, forKey: AnyCodingKey(ReactionUsageKey.reactions))
    }
}

extension ReactionUsageDocument: Codable {
    /// A missing `version` reads as version 1, a missing `rooms` as no
    /// rooms.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let version = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey(ReactionUsageKey.version))
            ?? Self.currentVersion
        let rooms = try container.decodeIfPresent([String: RoomReactionUsage].self, forKey: AnyCodingKey(ReactionUsageKey.rooms)) ?? [:]
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !ReactionUsageKey.documentKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.init(version: version, rooms: rooms, unknownFields: unknown)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(version, forKey: AnyCodingKey(ReactionUsageKey.version))
        try container.encode(rooms, forKey: AnyCodingKey(ReactionUsageKey.rooms))
    }
}

// MARK: - Reading and writing

/// The result of reading the reaction-usage account data (MATRIX-262).
public enum ReactionUsageReadResult: Equatable, Sendable {
    /// The account has no reaction-usage event yet. Writes start from an
    /// empty document.
    case empty
    case parsed(ReactionUsageDocument)
    /// The event exists but did not parse. The quick reactions rank without
    /// it, and every write is refused.
    case unreadable(raw: String, reason: String)

    /// The usage to rank by: none when the event is missing or unreadable.
    public var document: ReactionUsageDocument {
        switch self {
        case .empty, .unreadable: ReactionUsageDocument()
        case let .parsed(document): document
        }
    }

    /// The document a change may start from, or nil when writing is unsafe:
    /// the event is unreadable or has a newer `version`.
    public var writableBase: ReactionUsageDocument? {
        switch self {
        case .empty: ReactionUsageDocument()
        case let .parsed(document): document.isWritable ? document : nil
        case .unreadable: nil
        }
    }

    /// The parsed document, for the echo gate. Nil when the event is unset
    /// or did not parse.
    var parsedDocument: ReactionUsageDocument? {
        if case let .parsed(document) = self {
            return document
        }
        return nil
    }
}

public extension ReactionUsageDocument {
    /// Parses the account data content. `json` is nil when the event is
    /// unset.
    static func read(_ json: String?) -> ReactionUsageReadResult {
        guard let json else { return .empty }
        do {
            return try .parsed(JSONDecoder().decode(ReactionUsageDocument.self, from: Data(json.utf8)))
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
