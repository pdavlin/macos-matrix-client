import Foundation

// MATRIX-140: the JSON codec of the merged-chats account data.
//
// `MergedChat` and `MergedChatDocument` live in `MergedChat.swift`, which
// every M2.5 Phase A branch adds verbatim, so they cannot gain stored
// properties here. Fields this build does not know therefore live beside the
// document, in `MergedChatStoredDocument`, which is the one Codable type. A
// read-modify-write goes through it, so unknown fields survive at the top
// level and in each merge. `MergedChat` and `MergedChatDocument` are not
// Codable on purpose: encoding them directly would drop those fields.

/// A merged-chats document together with the JSON fields this build does not
/// know (MATRIX-140).
///
/// The wire format, with keys exactly as in `MergedChat.swift`:
///
/// ```json
/// {"version": 1, "merges": [{"id": "…", "name": "Seth",
///   "rooms": ["!a:davlin.io", "!b:davlin.io"],
///   "default_room": "!a:davlin.io", "avatar_room": "!b:davlin.io"}]}
/// ```
///
/// Unknown fields of a merge are kept by merge ID, so they follow the merge
/// through every mutation and go away with it when it is removed.
public struct MergedChatStoredDocument: Equatable, Sendable {
    /// The merged chats.
    public private(set) var document: MergedChatDocument
    /// Top-level fields this build does not know, written back unchanged.
    var unknownFields: [String: JSONValue]
    /// Fields of each merge this build does not know, by merge ID. Never
    /// holds an empty dictionary or the ID of a merge the document lacks, so
    /// two stored documents with the same content compare equal.
    var mergeUnknownFields: [String: [String: JSONValue]]

    /// A document with no unknown fields.
    public init(_ document: MergedChatDocument = MergedChatDocument()) {
        self.document = document
        unknownFields = [:]
        mergeUnknownFields = [:]
    }

    init(document: MergedChatDocument, unknownFields: [String: JSONValue], mergeUnknownFields: [String: [String: JSONValue]]) {
        self.document = document
        self.unknownFields = unknownFields
        self.mergeUnknownFields = mergeUnknownFields
        pruneMergeUnknownFields()
    }

    /// Applies `change` to the document, then restores the document's
    /// invariants (`MergedChatDocument.normalize()`) and drops the unknown
    /// fields of merges that no longer exist.
    public mutating func update(_ change: (inout MergedChatDocument) -> Void) {
        change(&document)
        document.normalize()
        pruneMergeUnknownFields()
    }

    private mutating func pruneMergeUnknownFields() {
        let ids = Set(document.merges.map(\.id))
        mergeUnknownFields = mergeUnknownFields.filter { ids.contains($0.key) && !$0.value.isEmpty }
    }
}

// MARK: - Codable

/// The JSON keys (contract §11, 2026-11-10).
private enum MergedChatKey {
    static let version = "version"
    static let merges = "merges"
    static let id = "id"
    static let name = "name"
    static let rooms = "rooms"
    static let defaultRoom = "default_room"
    static let avatarRoom = "avatar_room"

    static let documentKeys: Set<String> = [version, merges]
    static let mergeKeys: Set<String> = [id, name, rooms, defaultRoom, avatarRoom]
}

/// One merge on the wire: the known fields plus the ones this build does
/// not know.
private struct StoredMerge: Codable {
    var merge: MergedChat
    var unknownFields: [String: JSONValue]

    init(merge: MergedChat, unknownFields: [String: JSONValue]) {
        self.merge = merge
        self.unknownFields = unknownFields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let rooms = try container.decode([String].self, forKey: AnyCodingKey(MergedChatKey.rooms))
        merge = try MergedChat(
            id: container.decode(String.self, forKey: AnyCodingKey(MergedChatKey.id)),
            name: container.decode(String.self, forKey: AnyCodingKey(MergedChatKey.name)),
            rooms: rooms.uniqued(),
            defaultRoom: container.decodeIfPresent(String.self, forKey: AnyCodingKey(MergedChatKey.defaultRoom)),
            avatarRoom: container.decodeIfPresent(String.self, forKey: AnyCodingKey(MergedChatKey.avatarRoom))
        )
        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !MergedChatKey.mergeKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        unknownFields = unknown
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(merge.id, forKey: AnyCodingKey(MergedChatKey.id))
        try container.encode(merge.name, forKey: AnyCodingKey(MergedChatKey.name))
        try container.encode(merge.rooms, forKey: AnyCodingKey(MergedChatKey.rooms))
        try container.encodeIfPresent(merge.defaultRoom, forKey: AnyCodingKey(MergedChatKey.defaultRoom))
        try container.encodeIfPresent(merge.avatarRoom, forKey: AnyCodingKey(MergedChatKey.avatarRoom))
    }
}

extension MergedChatStoredDocument: Codable {
    /// Decodes the account data content.
    ///
    /// A missing `version` reads as version 1 (the §11 row shows content
    /// without one). A missing `merges` reads as no merges. Two merges with
    /// the same `id` fail the decode: every mutation names a merge by ID, so
    /// such a document cannot be edited safely.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        let version = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey(MergedChatKey.version))
            ?? MergedChatDocument.currentVersion
        let stored = try container.decodeIfPresent([StoredMerge].self, forKey: AnyCodingKey(MergedChatKey.merges)) ?? []

        var seenIds = Set<String>()
        var mergeUnknown: [String: [String: JSONValue]] = [:]
        for entry in stored {
            guard seenIds.insert(entry.merge.id).inserted else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath + [AnyCodingKey(MergedChatKey.merges) as CodingKey],
                    debugDescription: "two merges share the id \(entry.merge.id)"
                ))
            }
            mergeUnknown[entry.merge.id] = entry.unknownFields
        }

        var unknown: [String: JSONValue] = [:]
        for key in container.allKeys where !MergedChatKey.documentKeys.contains(key.stringValue) {
            unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }

        self.init(
            document: MergedChatDocument(version: version, merges: stored.map(\.merge)),
            unknownFields: unknown,
            mergeUnknownFields: mergeUnknown
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields {
            try container.encode(value, forKey: AnyCodingKey(key))
        }
        try container.encode(document.version, forKey: AnyCodingKey(MergedChatKey.version))
        let merges = document.merges.map { StoredMerge(merge: $0, unknownFields: mergeUnknownFields[$0.id] ?? [:]) }
        try container.encode(merges, forKey: AnyCodingKey(MergedChatKey.merges))
    }
}

// MARK: - Reading and writing

/// The result of reading the merged-chats account data (MATRIX-140).
public enum MergedChatReadResult: Equatable, Sendable {
    /// The account has no merged-chats event yet. Writes start from an
    /// empty document.
    case empty
    /// The event parsed.
    case parsed(MergedChatStoredDocument)
    /// The event exists but did not parse. The raw content is kept for the
    /// log. The app shows no merged chats and refuses every write, so a bug
    /// in this build cannot destroy data it could not read.
    case unreadable(raw: String, reason: String)

    /// The merged chats to show: none when the event is missing or
    /// unreadable. A parsed document of a newer version is shown as read.
    public var document: MergedChatDocument {
        switch self {
        case .empty, .unreadable: MergedChatDocument()
        case let .parsed(stored): stored.document
        }
    }

    /// The document a mutation may start from, or nil when writing is
    /// unsafe: the event is unreadable or has a newer `version`.
    public var writableBase: MergedChatStoredDocument? {
        switch self {
        case .empty: MergedChatStoredDocument()
        case let .parsed(stored): stored.document.isWritable ? stored : nil
        case .unreadable: nil
        }
    }
}

public extension MergedChatDocument {
    /// Parses the account data content. `json` is nil when the event is
    /// unset.
    static func read(_ json: String?) -> MergedChatReadResult {
        guard let json else { return .empty }
        do {
            return try .parsed(JSONDecoder().decode(MergedChatStoredDocument.self, from: Data(json.utf8)))
        } catch {
            return .unreadable(raw: json, reason: String(describing: error))
        }
    }
}

public extension MergedChatStoredDocument {
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
