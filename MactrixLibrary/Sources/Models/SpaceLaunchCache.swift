import Foundation

/// One joined space, as the space graph and its launch cache keep it
/// (MATRIX-170).
public struct KnownSpace: Codable, Hashable, Sendable {
    /// The space's room ID.
    public var id: String
    public var name: String
    /// The `mxc://` URL of the space's icon, or nil when it has none.
    public var avatarUrl: String?

    public init(id: String, name: String, avatarUrl: String? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

/// The last known space data of a session, kept in one JSON file so the
/// first frame after a launch is right (MATRIX-170).
///
/// The SDK builds its space graph some seconds after the launch. Until then
/// its list of joined spaces is empty and it answers "no parent space" for
/// each room, so the rail has no space items, the chat rows have no
/// workspace icon, and a restored space filter shows the Inbox. This file
/// holds the answers of the last session. `SpaceGraph` holds the rules that
/// say when a live answer replaces them.
///
/// The file is `<session cache folder>/SpaceLaunchCache.json`. The sign-out
/// removes the folder. The file holds room IDs, space names and icon URLs,
/// the same data the SDK store beside it holds. It holds no message content.
///
/// Format, version 1:
/// ```json
/// {
///   "version": 1,
///   "emptyLaunches": 0,
///   "topLevel": [{"id": "!dev:a", "name": "DevObsessed", "avatarUrl": "mxc://a/dev"}],
///   "rooms": {
///     "!chat:a": {"parents": [{"id": "!sub:a", "name": "Team"}], "unconfirmedLaunches": 0},
///     "!sub:a": {"parents": [{"id": "!dev:a", "name": "DevObsessed"}], "unconfirmedLaunches": 0}
///   }
/// }
/// ```
/// - `topLevel`: the top-level joined spaces, in the SDK's order.
/// - `rooms`: the direct joined parent spaces by child room ID. A child is a
///   chat or a sub-space, so the links from a sub-space to its parent are
///   here too. A room with no parent space has no entry.
/// - `unconfirmedLaunches`: how many sessions with a ready graph ended with
///   no live answer for the room. An entry at `maxUnconfirmedLaunches` is not
///   loaded: a room the account left does not stay in the file.
/// - `emptyLaunches` (MATRIX-186): how many sessions in a row synced, ended
///   their retry rounds, and got no space from the SDK. A file at
///   `maxUnconfirmedLaunches` is not loaded: an account that left all its
///   spaces does not keep them. A file with no key has a count of zero.
///
/// A file that does not decode, or has a different version, loads as an
/// empty cache.
public struct SpaceLaunchCache: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    /// The entry of a room, or the whole file for `emptyLaunches`, is
    /// dropped at this count: see the type.
    public static let maxUnconfirmedLaunches = 3

    /// The cache record of one child room.
    public struct Room: Codable, Equatable, Sendable {
        public var parents: [KnownSpace]
        public var unconfirmedLaunches: Int

        public init(parents: [KnownSpace], unconfirmedLaunches: Int = 0) {
            self.parents = parents
            self.unconfirmedLaunches = unconfirmedLaunches
        }
    }

    public var version: Int
    public var topLevel: [KnownSpace]
    public var rooms: [String: Room]
    /// See the type (MATRIX-186).
    public var emptyLaunches: Int

    public init(topLevel: [KnownSpace] = [], rooms: [String: Room] = [:], emptyLaunches: Int = 0) {
        version = Self.currentVersion
        self.topLevel = topLevel
        self.rooms = rooms
        self.emptyLaunches = emptyLaunches
    }

    private enum CodingKeys: String, CodingKey {
        case version, topLevel, rooms, emptyLaunches
    }

    /// A file of MATRIX-170 has no `emptyLaunches`: it decodes with a count
    /// of zero, so the update keeps the cache.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        topLevel = try container.decode([KnownSpace].self, forKey: .topLevel)
        rooms = try container.decode([String: Room].self, forKey: .rooms)
        emptyLaunches = try container.decodeIfPresent(Int.self, forKey: .emptyLaunches) ?? 0
    }

    /// Whether the cache holds no space and no room.
    public var isEmpty: Bool {
        topLevel.isEmpty && rooms.isEmpty
    }

    /// The cache in `data`, or an empty cache when `data` does not decode or
    /// has a different version.
    public static func decode(_ data: Data) -> SpaceLaunchCache {
        guard let cache = try? JSONDecoder().decode(SpaceLaunchCache.self, from: data),
              cache.version == currentVersion
        else { return SpaceLaunchCache() }
        return cache
    }

    /// The file's content. The keys are sorted, so equal caches give equal
    /// data.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Cache file

public extension SpaceLaunchCache {
    /// The cache file in a session's cache folder.
    static func file(in directory: URL) -> URL {
        directory.appending(component: "SpaceLaunchCache.json")
    }

    /// Reads the cache file. No file, or a file that cannot be read, gives
    /// an empty cache. The file is small: the read is synchronous so the
    /// data is there before the first frame.
    static func read(at url: URL) -> SpaceLaunchCache {
        guard let data = try? Data(contentsOf: url) else { return SpaceLaunchCache() }
        return decode(data)
    }

    /// Writes the cache file.
    ///
    /// - Returns: nil, or a short name of what went wrong, safe for the log.
    static func write(_ cache: SpaceLaunchCache, to url: URL) async -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try cache.encoded().write(to: url, options: .atomic)
            return nil
        } catch {
            return RoomStateReader.logName(of: error)
        }
    }
}

/// The joined spaces and the parent spaces of each room, from the launch
/// cache and then from the SDK (MATRIX-170).
///
/// The rule for a live answer:
///
/// - A live answer that is not empty replaces the cached value for that room
///   or list.
/// - A live answer that is empty is real only when **the graph is ready**.
///   Before that, the SDK gives an empty answer for each room and an empty
///   list of spaces, so an empty answer keeps the cached value.
/// - The graph is ready when there is evidence that the SDK built it:
///   1. the SDK's list of top-level joined spaces is not empty, or
///   2. one room got a parent list that is not empty in this session.
/// - Time is not evidence (MATRIX-186). The SDK can build its graph a minute
///   or more after the launch, after the caller's retry rounds ended. When
///   the rounds end after a sync with no evidence, the session is an
///   **empty session**: the cached values stay in this session and in the
///   file, and the file counts the session (`emptyLaunches`). After
///   `maxUnconfirmedLaunches` empty sessions in a row the file is not
///   loaded: that account has no space. A session with evidence sets the
///   count to zero.
/// - With no sync in this session the session is not counted (MATRIX-171).
///   With no network the SDK never builds its space graph, so its empty
///   answers say nothing: the cache file stays as it is.
///   `SessionSyncEvidence` says what a sync is.
/// - After the graph is ready, an empty answer clears the value.
/// - An empty answer that came before the graph was ready is held. The
///   caller reads those rooms again (its retry rounds). When the graph is
///   ready, `finishRetries(hasSynced:)` clears the held rooms that are left.
///
/// A space the account left goes away with these rules: a live list of
/// spaces that is not empty replaces the cached list, and each room's live
/// answer replaces the room's cached parents.
///
/// No clock and no I/O: the caller owns the retry timing and the file.
public struct SpaceGraph: Equatable, Sendable {
    /// The top-level joined spaces, in the SDK's order.
    public private(set) var topLevel: [KnownSpace]

    /// The direct joined parent spaces by child room ID. A room with a live
    /// answer of "no parent" has an empty list. A room with no answer and no
    /// cached value has no entry.
    public private(set) var parents: [String: [KnownSpace]] = [:]

    /// Whether there is evidence that the SDK built its space graph: see the
    /// type.
    public private(set) var isReady = false

    /// The file's `unconfirmedLaunches` of the rooms that have a cached
    /// value and no live answer yet.
    private var unconfirmed: [String: Int] = [:]

    /// The rooms with a cached value whose live answer was empty before the
    /// graph was ready.
    private var heldEmpty: Set<String> = []

    /// The file's `emptyLaunches`.
    private var emptyLaunches = 0

    /// Whether this session is an empty session: see the type.
    private var isEmptySession = false

    /// - Parameter cache: the launch cache, or an empty cache.
    public init(cache: SpaceLaunchCache = SpaceLaunchCache()) {
        guard cache.emptyLaunches < SpaceLaunchCache.maxUnconfirmedLaunches else {
            topLevel = []
            return
        }
        topLevel = cache.topLevel
        emptyLaunches = max(0, cache.emptyLaunches)
        for (roomId, room) in cache.rooms {
            guard !room.parents.isEmpty, room.unconfirmedLaunches < SpaceLaunchCache.maxUnconfirmedLaunches else { continue }
            parents[roomId] = room.parents
            unconfirmed[roomId] = max(0, room.unconfirmedLaunches)
        }
    }

    /// Whether a cached value is in use: a cached list of spaces or a cached
    /// room, before the graph is ready.
    public var holdsCachedData: Bool {
        !isReady && (!topLevel.isEmpty || !unconfirmed.isEmpty)
    }

    /// The chats the cache knows, for the time before the graph is ready:
    /// the cached rooms that are not a space. Empty when the graph is ready,
    /// because the live room list is complete then.
    ///
    /// The rail shows a space only when it holds a chat, and the live room
    /// list is also empty in the first frames. With these IDs the rail and
    /// a restored space filter are right at once.
    public var launchChatIds: Set<String> {
        guard !isReady else { return [] }
        var spaceIds = Set(topLevel.map(\.id))
        for list in parents.values {
            spaceIds.formUnion(list.map(\.id))
        }
        return Set(unconfirmed.keys).subtracting(spaceIds)
    }

    /// Takes the SDK's list of top-level joined spaces.
    public mutating func setTopLevel(_ live: [KnownSpace]) {
        if !live.isEmpty {
            isReady = true
        }
        if isReady, topLevel != live {
            topLevel = live
        }
    }

    /// Takes the SDK's answer for the parent spaces of one room.
    public mutating func setParents(_ live: [KnownSpace], of roomId: String) {
        if !live.isEmpty {
            isReady = true
        }
        if !isReady, unconfirmed[roomId] != nil {
            heldEmpty.insert(roomId)
            return
        }
        parents[roomId] = live
        unconfirmed[roomId] = nil
        heldEmpty.remove(roomId)
    }

    /// The caller's retry rounds ended.
    ///
    /// - With no sync nothing changes (MATRIX-171): the cached values and
    ///   the held answers stay, and the caller runs its rounds again after
    ///   the sync.
    /// - With a sync and a ready graph, each held empty answer clears its
    ///   room.
    /// - With a sync and no evidence, the session is an empty session
    ///   (MATRIX-186): the cached values stay, and `cache` counts the
    ///   session. The SDK can still build its graph later in the session.
    ///
    /// - Parameter hasSynced: `SessionSyncEvidence.hasSynced`.
    public mutating func finishRetries(hasSynced: Bool) {
        guard hasSynced else { return }
        guard isReady else {
            if holdsCachedData {
                isEmptySession = true
            }
            return
        }
        for roomId in heldEmpty {
            parents[roomId] = []
            unconfirmed[roomId] = nil
        }
        heldEmpty = []
    }

    /// What to write to the cache file.
    ///
    /// A room with a live answer has a count of zero. A cached room with no
    /// live answer keeps its count, plus one when the graph is ready: a
    /// session that ended before the graph was ready says nothing about the
    /// room.
    ///
    /// `emptyLaunches` is zero when the graph is ready, and the file's count
    /// plus one after an empty session.
    public var cache: SpaceLaunchCache {
        var rooms: [String: SpaceLaunchCache.Room] = [:]
        for (roomId, list) in parents where !list.isEmpty {
            let count = unconfirmed[roomId].map { $0 + (isReady ? 1 : 0) } ?? 0
            rooms[roomId] = SpaceLaunchCache.Room(parents: list, unconfirmedLaunches: count)
        }
        let empty = isReady ? 0 : emptyLaunches + (isEmptySession ? 1 : 0)
        return SpaceLaunchCache(topLevel: topLevel, rooms: rooms, emptyLaunches: empty)
    }
}

/// Whether the client has synced in this app session (MATRIX-171).
///
/// `SpaceGraph` takes an empty answer of the SDK as real only after a sync:
/// with no network the SDK never builds its space graph, and its empty
/// answers must not clear the rail and the launch cache.
///
/// The evidence is the room list service in `running` (MATRIX-186). The
/// service starts in `initial` and goes to `settingUp` for its first
/// request. The bindings do not say that `settingUp` comes after a server
/// answer, so it is not evidence: `running` comes only after the answer to
/// the `settingUp` request. A start with no network goes to `error`,
/// `terminated` or `recovering`. The state of the sync service is not
/// evidence: it is `running` from the start of the sync, before the first
/// response.
///
/// The value is a latch: a later loss of the network does not clear it,
/// because the SDK built its graph from the sync that came before.
public struct SessionSyncEvidence: Equatable, Sendable {
    /// The states of the SDK's room list service.
    public enum RoomListState: Equatable, Sendable, CaseIterable {
        case initial, settingUp, recovering, running, error, terminated

        /// Whether the state comes only after a sync response.
        public var showsSync: Bool {
            switch self {
            case .running: true
            case .initial, .settingUp, .recovering, .error, .terminated: false
            }
        }
    }

    /// Whether a sync response came in this session.
    public private(set) var hasSynced = false

    public init() {}

    /// Takes a state of the room list service.
    ///
    /// - Returns: whether this state is the first evidence of a sync.
    @discardableResult
    public mutating func note(_ state: RoomListState) -> Bool {
        guard !hasSynced, state.showsSync else { return false }
        hasSynced = true
        return true
    }
}
