import Foundation

/// Every label of the account, as stored in global account data (MATRIX-77).
///
/// The event type is `io.davlin.mactrix.labels` and the content is:
///
/// ```json
/// {"version": 1, "labels": [{"id": "…", "name": "Work", "colorIndex": 3,
///   "icon": "briefcase", "muted": false, "inboxVisibility": "all",
///   "rooms": ["!a:example.org"]}]}
/// ```
///
/// Array order is rail order. Fields this build does not know, at the top
/// level and in each label, survive a read-modify-write.
public struct ChatLabelDocument: Equatable, Sendable {
    /// The global account data event type.
    public static let eventType = "io.davlin.mactrix.labels"

    /// The schema version this build writes.
    public static let currentVersion = 1

    public var version: Int
    public var labels: [ChatLabel]
    /// Top-level fields this build does not know, written back unchanged.
    var unknownFields: [String: JSONValue]

    public init(labels: [ChatLabel] = []) {
        self.version = Self.currentVersion
        self.labels = labels
        self.unknownFields = [:]
    }

    /// This build may write the document. A newer schema version is read but
    /// never written: a later build may have changed what a field means.
    public var isWritable: Bool {
        version <= Self.currentVersion
    }
}

extension ChatLabelDocument: Codable {
    private static let knownKeys: Set<String> = ["version", "labels"]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        version = try container.decode(Int.self, forKey: AnyCodingKey("version"))
        labels = try container.decodeIfPresent([ChatLabel].self, forKey: AnyCodingKey("labels")) ?? []

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
        try container.encode(version, forKey: AnyCodingKey("version"))
        try container.encode(labels, forKey: AnyCodingKey("labels"))
    }
}

// MARK: - Reading and writing

/// The result of reading the labels account data.
public enum ChatLabelReadResult: Equatable, Sendable {
    /// The account has no labels event yet. Writes start from an empty
    /// document.
    case empty
    /// The event parsed.
    case parsed(ChatLabelDocument)
    /// The event exists but did not parse. The raw content is kept for the
    /// log; the app shows no labels and refuses every write, so a bug in this
    /// build cannot destroy data it could not read.
    case unreadable(raw: String, reason: String)

    /// The labels to show: none when the event is missing or unreadable.
    public var document: ChatLabelDocument {
        switch self {
        case .empty, .unreadable: ChatLabelDocument()
        case let .parsed(document): document
        }
    }

    /// The document a mutation may start from, or nil when writing is unsafe.
    public var writableBase: ChatLabelDocument? {
        switch self {
        case .empty: ChatLabelDocument()
        case let .parsed(document): document.isWritable ? document : nil
        case .unreadable: nil
        }
    }
}

public extension ChatLabelDocument {
    /// Parses the account data content. `json` is nil when the event is unset.
    static func read(_ json: String?) -> ChatLabelReadResult {
        guard let json else { return .empty }
        do {
            return try .parsed(JSONDecoder().decode(ChatLabelDocument.self, from: Data(json.utf8)))
        } catch {
            return .unreadable(raw: json, reason: String(describing: error))
        }
    }

    /// The content to write. Keys are sorted so equal documents encode to the
    /// same string.
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

// MARK: - Queries

public extension ChatLabelDocument {
    func label(id: String) -> ChatLabel? {
        labels.first { $0.id == id }
    }

    /// The labels that hold `roomId`, in rail order.
    func labels(containing roomId: String) -> [ChatLabel] {
        labels.filter { $0.rooms.contains(roomId) }
    }

    /// Every room in at least one label.
    var labelledRoomIds: Set<String> {
        Set(labels.flatMap(\.rooms))
    }

    /// Rooms the Inbox leaves out.
    ///
    /// Beeper's rule: a room in ANY label whose inbox visibility is hidden is
    /// hidden from the Inbox, even if another label of the room shows in it.
    /// Hiding is the explicit choice, so it wins.
    var inboxHiddenRoomIds: Set<String> {
        Set(labels.lazy.filter { !$0.isShownInInbox }.flatMap(\.rooms))
    }

    /// Rooms Mactrix treats as muted because of their labels.
    ///
    /// Beeper's rule (`isRoomMutedByLabels`): a room is muted by labels only
    /// when it is in at least one label and EVERY label that holds it is
    /// muted. One unmuted label keeps the room audible.
    var labelMutedRoomIds: Set<String> {
        var allMuted: [String: Bool] = [:]
        for label in labels {
            for room in label.rooms {
                allMuted[room] = (allMuted[room] ?? true) && label.isMuted
            }
        }
        return Set(allMuted.lazy.filter(\.value).map(\.key))
    }

    func isRoomMutedByLabels(_ roomId: String) -> Bool {
        let holding = labels(containing: roomId)
        return !holding.isEmpty && holding.allSatisfy(\.isMuted)
    }
}

// MARK: - Mutations

// Every mutation names its label by ID, not by index: the app applies it to a
// freshly read document, where another window or device may have reordered
// or deleted labels since the user clicked. A mutation for a missing label is
// a no-op.

public extension ChatLabelDocument {
    /// Appends a label at the end of the rail and returns it.
    @discardableResult
    mutating func create(
        id: String = UUID().uuidString,
        name: String,
        colorIndex: Int? = nil,
        icon: String? = nil,
        rooms: [String] = []
    ) -> ChatLabel {
        let label = ChatLabel(id: id, name: name, colorIndex: colorIndex, icon: icon, rooms: rooms)
        labels.append(label)
        return label
    }

    mutating func rename(_ id: String, to name: String) {
        update(id) { $0.name = name }
    }

    mutating func setColor(_ id: String, colorIndex: Int?) {
        update(id) { $0.colorIndex = colorIndex }
    }

    mutating func setIcon(_ id: String, icon: String?) {
        update(id) { $0.icon = icon }
    }

    mutating func setMuted(_ id: String, _ isMuted: Bool) {
        update(id) { $0.isMuted = isMuted }
    }

    mutating func toggleMuted(_ id: String) {
        update(id) { $0.isMuted.toggle() }
    }

    mutating func setInboxVisibility(_ id: String, _ visibility: ChatLabelInboxVisibility) {
        update(id) { $0.inboxVisibility = visibility }
    }

    mutating func addRoom(_ roomId: String, to id: String) {
        update(id) { label in
            if !label.rooms.contains(roomId) {
                label.rooms.append(roomId)
            }
        }
    }

    mutating func removeRoom(_ roomId: String, from id: String) {
        update(id) { $0.rooms.removeAll { $0 == roomId } }
    }

    mutating func toggleRoom(_ roomId: String, in id: String) {
        if label(id: id)?.rooms.contains(roomId) == true {
            removeRoom(roomId, from: id)
        } else {
            addRoom(roomId, to: id)
        }
    }

    mutating func setRooms(_ rooms: [String], for id: String) {
        update(id) { $0.rooms = rooms.uniqued() }
    }

    /// Applies an edit-sheet draft to an existing label. Unknown fields of
    /// the label stay.
    mutating func apply(_ draft: ChatLabelDraft, to id: String) {
        update(id) { label in
            label.name = draft.trimmedName
            label.colorIndex = draft.colorIndex
            label.icon = draft.icon
            label.rooms = draft.rooms.uniqued()
        }
    }

    mutating func delete(_ id: String) {
        labels.removeAll { $0.id == id }
    }

    /// Moves a label to `index` in the rail, clamped to the valid range.
    mutating func move(_ id: String, to index: Int) {
        guard let from = labels.firstIndex(where: { $0.id == id }) else { return }
        let label = labels.remove(at: from)
        labels.insert(label, at: min(max(index, 0), labels.count))
    }

    private mutating func update(_ id: String, _ change: (inout ChatLabel) -> Void) {
        guard let index = labels.firstIndex(where: { $0.id == id }) else { return }
        change(&labels[index])
    }
}
