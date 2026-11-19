import Foundation

// MATRIX-208: bookmarked messages, kept in global account data.
//
// Account data is not encrypted on the server, so a bookmark holds the room
// ID, the event ID, and the time it was saved. Never message text: the list
// reads the preview through the SDK when it shows (contract §11,
// 2026-11-19).

/// The message a bookmark points at: its room and its event.
public struct BookmarkKey: Hashable, Sendable {
    /// The room that holds the event. In a merged chat, the member room.
    public var roomId: String
    public var eventId: String

    public init(roomId: String, eventId: String) {
        self.roomId = roomId
        self.eventId = eventId
    }
}

/// One bookmarked message (MATRIX-208).
public struct Bookmark: Equatable, Sendable, Identifiable {
    public var key: BookmarkKey
    /// When the account saved the bookmark. The list sorts by it.
    public var savedAt: Date
    /// Fields of this entry that this build does not know, written back
    /// unchanged.
    var unknownFields: [String: JSONValue]

    public var id: BookmarkKey { key }
    public var roomId: String { key.roomId }
    public var eventId: String { key.eventId }

    public init(roomId: String, eventId: String, savedAt: Date) {
        self.init(key: BookmarkKey(roomId: roomId, eventId: eventId), savedAt: savedAt, unknownFields: [:])
    }

    init(key: BookmarkKey, savedAt: Date, unknownFields: [String: JSONValue]) {
        self.key = key
        self.savedAt = savedAt
        self.unknownFields = unknownFields
    }
}

/// The account's bookmarks (MATRIX-208).
///
/// Stored in global account data under `BookmarkDocument.eventType`:
///
/// ```json
/// {"version": 1, "bookmarks": [
///   {"room_id": "!a:davlin.io", "event_id": "$e", "saved_at": 1800000000000}]}
/// ```
///
/// `saved_at` is milliseconds since the Unix epoch, as Matrix timestamps
/// are. Fields this build does not know survive a read-modify-write, at the
/// top level and in each entry. A key is in the list at most once.
public struct BookmarkDocument: Equatable, Sendable {
    /// The global account-data event type (contract §11, 2026-11-19).
    public static let eventType = "io.davlin.matrixclient.bookmarks"

    /// The schema version this build writes.
    public static let currentVersion = 1

    public var version: Int
    /// The bookmarks in stored order: the oldest saved first, as each new
    /// one is appended.
    public private(set) var bookmarks: [Bookmark]
    /// Top-level fields this build does not know.
    var unknownFields: [String: JSONValue]

    public init(version: Int = BookmarkDocument.currentVersion, bookmarks: [Bookmark] = []) {
        self.init(version: version, bookmarks: bookmarks, unknownFields: [:])
    }

    init(version: Int, bookmarks: [Bookmark], unknownFields: [String: JSONValue]) {
        self.version = version
        var seen = Set<BookmarkKey>()
        // A key twice keeps its first entry, so the list has one row per
        // message and a removal removes it completely.
        self.bookmarks = bookmarks.filter { seen.insert($0.key).inserted }
        self.unknownFields = unknownFields
    }

    /// This build may write the document. A newer schema is read but never
    /// overwritten.
    public var isWritable: Bool {
        version <= Self.currentVersion
    }

    /// Every bookmarked message.
    public var keys: Set<BookmarkKey> {
        Set(bookmarks.map(\.key))
    }

    public func contains(_ key: BookmarkKey) -> Bool {
        bookmarks.contains { $0.key == key }
    }

    /// The bookmarks as the list shows them: the newest saved first. Two
    /// with the same time keep the later stored one first.
    public var newestFirst: [Bookmark] {
        bookmarks.enumerated()
            .sorted { lhs, rhs in
                lhs.element.savedAt != rhs.element.savedAt ? lhs.element.savedAt > rhs.element.savedAt : lhs.offset > rhs.offset
            }
            .map(\.element)
    }

    /// Bookmarks or removes the bookmark of `key`. It states the wanted
    /// value, so a change queued behind another device's write stays
    /// correct. Saving a key that is already saved keeps its first time.
    public mutating func setBookmarked(_ key: BookmarkKey, _ isBookmarked: Bool, savedAt: Date = .now) {
        if isBookmarked {
            guard !contains(key) else { return }
            // The wire keeps milliseconds. Round now, so the written
            // document equals its sync echo (`AccountDataEchoGate`).
            bookmarks.append(Bookmark(key: key, savedAt: Bookmark.wireDate(Bookmark.wireMilliseconds(savedAt)), unknownFields: [:]))
        } else {
            bookmarks.removeAll { $0.key == key }
        }
    }
}

// MARK: - Codable

private enum BookmarkKeyName {
    static let version = "version"
    static let bookmarks = "bookmarks"
    static let roomId = "room_id"
    static let eventId = "event_id"
    static let savedAt = "saved_at"

    static let documentKeys: Set<String> = [version, bookmarks]
    static let entryKeys: Set<String> = [roomId, eventId, savedAt]
}

extension Bookmark: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let milliseconds = try container.decode(Int64.self, forKey: AnyCodingKey(BookmarkKeyName.savedAt))
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !BookmarkKeyName.entryKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        try self.init(
            key: BookmarkKey(
                roomId: container.decode(String.self, forKey: AnyCodingKey(BookmarkKeyName.roomId)),
                eventId: container.decode(String.self, forKey: AnyCodingKey(BookmarkKeyName.eventId))
            ),
            savedAt: Self.wireDate(milliseconds),
            unknownFields: unknown
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(roomId, forKey: AnyCodingKey(BookmarkKeyName.roomId))
        try container.encode(eventId, forKey: AnyCodingKey(BookmarkKeyName.eventId))
        try container.encode(Self.wireMilliseconds(savedAt), forKey: AnyCodingKey(BookmarkKeyName.savedAt))
    }

    static func wireMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    static func wireDate(_ milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }
}

extension BookmarkDocument: Codable {
    /// A missing `version` reads as version 1, a missing `bookmarks` as no
    /// bookmarks. An entry without its IDs or time fails the decode: the
    /// app then refuses every write, so it cannot drop entries it could not
    /// read.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let version = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey(BookmarkKeyName.version))
            ?? Self.currentVersion
        let bookmarks = try container.decodeIfPresent([Bookmark].self, forKey: AnyCodingKey(BookmarkKeyName.bookmarks)) ?? []
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !BookmarkKeyName.documentKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.init(version: version, bookmarks: bookmarks, unknownFields: unknown)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(version, forKey: AnyCodingKey(BookmarkKeyName.version))
        try container.encode(bookmarks, forKey: AnyCodingKey(BookmarkKeyName.bookmarks))
    }
}

// MARK: - Reading and writing

/// The result of reading the bookmarks account data (MATRIX-208).
public enum BookmarkReadResult: Equatable, Sendable {
    /// The account has no bookmarks event yet. Writes start from an empty
    /// document.
    case empty
    case parsed(BookmarkDocument)
    /// The event exists but did not parse. The app shows no bookmarks and
    /// refuses every write.
    case unreadable(raw: String, reason: String)

    /// The bookmarks to show.
    public var document: BookmarkDocument {
        switch self {
        case .empty, .unreadable: BookmarkDocument()
        case let .parsed(document): document
        }
    }

    /// The document a change may start from, or nil when writing is unsafe:
    /// the event is unreadable or has a newer `version`.
    public var writableBase: BookmarkDocument? {
        switch self {
        case .empty: BookmarkDocument()
        case let .parsed(document): document.isWritable ? document : nil
        case .unreadable: nil
        }
    }
}

public extension BookmarkDocument {
    /// Parses the account data content. `json` is nil when the event is
    /// unset.
    static func read(_ json: String?) -> BookmarkReadResult {
        guard let json else { return .empty }
        do {
            return try .parsed(JSONDecoder().decode(BookmarkDocument.self, from: Data(json.utf8)))
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
