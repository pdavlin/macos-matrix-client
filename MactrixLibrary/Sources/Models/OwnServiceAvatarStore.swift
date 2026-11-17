import Foundation

/// The user's own profile image on each bridged service, by workspace space
/// (MATRIX-165).
///
/// A bridge puts each chat of a Slack workspace in the workspace's space.
/// With double puppeting the user's own ghost of that workspace is in no
/// room, so the store learns it in two steps:
///
/// 1. **The ghost.** It reads the state of one direct chat of the space,
///    takes the receiver of its bridge info (`BridgeInfo`), and derives the
///    ghost's user ID from the peer's ghost ID (`OwnServiceGhost`).
/// 2. **The image.** It reads the ghost's profile, and keeps the avatar URL.
///
/// The store has no SDK and no network of its own: `Source` gives it the
/// parent lookup, the candidate chats, the state read (`RoomStateReader`),
/// the profile read, and the cache folder, so tests run from fixtures.
///
/// Rules:
/// - A space has one load in flight: a second `load` in that time is dropped.
/// - Step 1 makes at most `maxStateReads` state reads per space in one app
///   session. After a search that did not give the ghost, the next search
///   waits `retryInterval`. A chat that gave a final answer (no receiver, or
///   no usable peer) is not read again.
/// - A space with no usable direct chat is `resolved(avatarUrl: nil)`: the
///   row keeps the MATRIX-163 order. After `maxStateReads` reads, or
///   `maxEmptySearches` searches that found no chat, that is the answer for
///   the session.
/// - The ghost is kept in the cache file, so step 1 runs once per workspace,
///   not once per session.
/// - A kept ghost is checked (MATRIX-171): a new login to the workspace
///   gives a new receiver, and the old ghost has the old image. The store
///   reads the receiver again when `OwnServiceReceiverCheck` says so: at
///   most once per `OwnServiceReceiverCheck.interval`, and one time per
///   session when the ghost's profile read fails with `ProfileNotFound`. A
///   receiver that changed replaces the ghost. A check that gives no
///   receiver keeps the ghost. The check uses the limits of step 1.
/// - Step 2 runs when the last good profile read is older than
///   `profileRefreshInterval`, or was never made. After `maxFailedReads`
///   failed reads in a row it waits `retryInterval` (`ReadSchedule`). A read
///   that fails leaves a known image as it is.
/// - "No parent space" is not kept: the SDK gives that answer until its space
///   graph is ready (`RoomAccountNames`), so the next call asks again.
/// - The cache file holds the receiver, the ghost's user ID, the avatar URL,
///   the time of the profile read, and the time of the receiver check. It
///   never holds the room state.
///
/// Presentation only: a wrong or absent value changes one image.
///
/// Usage (in `Core`):
/// ```swift
/// await store.load(roomId: room.id, from: source)
/// let url = store.avatarUrl(forRoom: room.id)
/// ```
@MainActor @Observable
public final class OwnServiceAvatarStore {
    /// What the store knows about one space.
    public enum State: Equatable, Sendable {
        /// No answer yet.
        case unknown
        /// The answer. A nil URL means no service image: the space has no
        /// usable direct chat, or the ghost's profile has no avatar.
        case resolved(avatarUrl: String?)
        /// A read failed and no earlier answer exists.
        case failed
    }

    /// A direct chat that can tell the own ghost of its space.
    public struct Candidate: Equatable, Sendable {
        public let roomId: String
        /// The user IDs that can be the peer's ghost, see
        /// `OwnServiceGhost.peers(among:serviceMembers:accountUserId:)`.
        public let peerUserIds: [String]

        public init(roomId: String, peerUserIds: [String]) {
            self.roomId = roomId
            self.peerUserIds = peerUserIds
        }
    }

    /// The cache record of one space.
    public struct Record: Codable, Equatable, Sendable {
        /// The receiver of the direct chat's bridge info.
        public let receiver: String
        /// The user ID of the own ghost.
        public let ghostUserId: String
        /// The ghost's avatar, an `mxc://` URL. Nil without one, and before
        /// the first good profile read.
        public var avatarUrl: String?
        /// The time of the last good profile read, or nil before the first.
        public var profileReadAt: Date?
        /// The time of the last read that gave `receiver` (MATRIX-171). Nil
        /// in a file of an earlier version: the receiver is read again.
        public var receiverCheckedAt: Date?
    }

    /// The error of `Source.fetchAvatarUrl` when the server has no profile
    /// for the user.
    public struct ProfileNotFound: Error, Equatable {
        public init() {}
    }

    /// What the store reads from.
    public struct Source: Sendable {
        /// The folder of the cache files, or nil for no cache.
        public let cacheDirectory: URL?
        /// The signed-in account's Matrix ID.
        public let accountUserId: String
        /// The IDs of the joined parent spaces of a room.
        public let parentSpaces: @MainActor (_ roomId: String) async throws -> [String]
        /// At most `limit` direct chats of the space, the most recently
        /// active first, without the rooms in `excluding`.
        public let candidates: @MainActor (_ spaceId: String, _ excluding: Set<String>, _ limit: Int) async -> [Candidate]
        /// The state of a direct chat, as `BridgeInfo.receiver(roomState:)`
        /// reads it.
        public let fetchState: @MainActor (_ roomId: String) async throws -> Data
        /// The avatar URL of a user's global profile. Throws
        /// `ProfileNotFound` when the server has no profile for the user.
        public let fetchAvatarUrl: @MainActor (_ userId: String) async throws -> String?
        /// Takes one line for the log when a read fails. The line holds a
        /// space ID and an error name, never a token or a response body.
        public let report: @MainActor (String) -> Void

        public init(
            cacheDirectory: URL?,
            accountUserId: String,
            parentSpaces: @escaping @MainActor (_ roomId: String) async throws -> [String],
            candidates: @escaping @MainActor (_ spaceId: String, _ excluding: Set<String>, _ limit: Int) async -> [Candidate],
            fetchState: @escaping @MainActor (_ roomId: String) async throws -> Data,
            fetchAvatarUrl: @escaping @MainActor (_ userId: String) async throws -> String?,
            report: @escaping @MainActor (String) -> Void
        ) {
            self.cacheDirectory = cacheDirectory
            self.accountUserId = accountUserId
            self.parentSpaces = parentSpaces
            self.candidates = candidates
            self.fetchState = fetchState
            self.fetchAvatarUrl = fetchAvatarUrl
            self.report = report
        }
    }

    /// How old the last good profile read can be before a `load` reads the
    /// profile again.
    public static let profileRefreshInterval: TimeInterval = 24 * 60 * 60

    /// The wait after a search that did not give the ghost, and after
    /// `maxFailedReads` failed profile reads in a row.
    public static let retryInterval: TimeInterval = ImagePackStore.refreshInterval

    /// The failed profile reads in a row after which a space waits
    /// `retryInterval`.
    public static let maxFailedReads = ImagePackStore.maxFailedReads

    /// The most state reads (candidate chats) per space in one app session.
    public static let maxStateReads = 3

    /// The most searches per space in one app session that found no
    /// candidate chat.
    public static let maxEmptySearches = 3

    /// The state by space ID. A space with no entry is `unknown`.
    public private(set) var stateBySpace: [String: State] = [:]
    /// The parent space IDs by room ID, for the rooms that have a parent.
    public private(set) var spacesByRoom: [String: [String]] = [:]

    private struct Progress {
        var record: Record?
        var profile = ReadSchedule()
        var search = ReadSchedule()
        var stateReads = 0
        var emptySearches = 0
        /// The chats that gave a final answer without a ghost.
        var answeredRooms: Set<String> = []
        /// Whether a `ProfileNotFound` started a receiver check in this
        /// session.
        var checkedAfterNotFound = false
    }

    /// What one search of step 1 gave.
    private enum Search {
        /// The limits of the session or the wait did not permit a search.
        case skipped
        case found(receiver: String, ghostUserId: String)
        case noGhost(failed: Bool)
    }

    private let now: @MainActor () -> Date
    @ObservationIgnored private var progress: [String: Progress] = [:]
    @ObservationIgnored private var resolvingRooms: Set<String> = []
    @ObservationIgnored private var loads: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var cacheReadSpaces: Set<String> = []
    @ObservationIgnored private var cacheWrites: [String: Task<Void, Never>] = [:]

    /// - Parameter now: The clock. Tests give their own.
    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    /// The state of a space. The read is observable.
    public func state(ofSpace spaceId: String) -> State {
        stateBySpace[spaceId] ?? .unknown
    }

    /// The user's own image on the service of `roomId`: the avatar of the
    /// own ghost of the room's first parent space that has one. Nil until
    /// `load` found it, and for a room with none. The read is observable.
    public func avatarUrl(forRoom roomId: String) -> String? {
        for spaceId in spacesByRoom[roomId] ?? [] {
            if case let .resolved(avatarUrl?) = state(ofSpace: spaceId) {
                return avatarUrl
            }
        }
        return nil
    }

    /// Loads the own image for the room's parent spaces. Safe to call on
    /// each chat open: see the rules on the type.
    ///
    /// - Parameters:
    ///   - roomId: The room of the chat. In a merged chat, the member room.
    ///   - source: Where to read from.
    public func load(roomId: String, from source: Source) async {
        for spaceId in await parentSpaces(of: roomId, from: source) {
            guard loads[spaceId] == nil else { continue }
            let load = Task { await self.load(spaceId: spaceId, from: source) }
            loads[spaceId] = load
            await load.value
            loads[spaceId] = nil
        }
    }

    /// Returns when every cache write that a change started is on disk.
    public func waitForCacheWrites() async {
        while let (spaceId, write) = cacheWrites.first {
            await write.value
            if cacheWrites[spaceId] == write {
                cacheWrites[spaceId] = nil
            }
        }
    }

    // MARK: - Parent spaces

    private func parentSpaces(of roomId: String, from source: Source) async -> [String] {
        if let known = spacesByRoom[roomId] { return known }
        guard resolvingRooms.insert(roomId).inserted else { return [] }
        defer { resolvingRooms.remove(roomId) }
        do {
            let parents = try await source.parentSpaces(roomId)
            // An empty answer is not final: see the rules on the type.
            guard !parents.isEmpty else { return [] }
            spacesByRoom[roomId] = parents
            return parents
        } catch {
            source.report("failed to read the parent spaces of \(roomId): \(RoomStateReader.logName(of: error))")
            return []
        }
    }

    // MARK: - One space

    private func load(spaceId: String, from source: Source) async {
        if cacheReadSpaces.insert(spaceId).inserted {
            await readCache(of: spaceId, from: source)
        }
        var checkedReceiver = false
        if let record = progress[spaceId]?.record {
            if OwnServiceReceiverCheck.isDue(lastCheck: record.receiverCheckedAt, now: now(), profileNotFound: false) {
                checkedReceiver = true
                await checkReceiver(of: spaceId, from: source)
            }
        } else {
            await findGhost(of: spaceId, from: source)
        }
        guard let record = progress[spaceId]?.record else { return }
        let profileNotFound = await readProfile(of: spaceId, from: source)
        guard profileNotFound, !checkedReceiver, progress[spaceId]?.checkedAfterNotFound == false,
              OwnServiceReceiverCheck.isDue(lastCheck: record.receiverCheckedAt, now: now(), profileNotFound: true)
        else { return }
        progress[spaceId]?.checkedAfterNotFound = true
        if await checkReceiver(of: spaceId, from: source) {
            await readProfile(of: spaceId, from: source)
        }
    }

    /// Step 1: see the rules on the type.
    private func findGhost(of spaceId: String, from source: Source) async {
        var entry = progress[spaceId] ?? Progress()
        defer { progress[spaceId] = entry }
        switch await searchGhost(of: spaceId, entry: &entry, from: source) {
        case .skipped:
            return
        case let .found(receiver, ghostUserId):
            entry.record = Record(receiver: receiver, ghostUserId: ghostUserId, receiverCheckedAt: now())
        case let .noGhost(failed):
            // A failed read can still give the ghost later. No usable chat
            // means no service image.
            setState(failed ? .failed : .resolved(avatarUrl: nil), of: spaceId)
        }
    }

    /// The receiver check of a kept ghost (MATRIX-171): see the rules on the
    /// type.
    ///
    /// - Returns: whether the ghost changed.
    @discardableResult
    private func checkReceiver(of spaceId: String, from source: Source) async -> Bool {
        guard var entry = progress[spaceId], var record = entry.record else { return false }
        defer { progress[spaceId] = entry }
        guard case let .found(receiver, ghostUserId) = await searchGhost(of: spaceId, entry: &entry, from: source) else {
            return false
        }
        guard OwnServiceReceiverCheck.replacesGhost(cachedReceiver: record.receiver, liveReceiver: receiver) else {
            record.receiverCheckedAt = now()
            entry.record = record
            writeCache(record, of: spaceId, from: source)
            return false
        }
        // The image of the old ghost is the image of another login. The
        // profile read that follows writes the cache file.
        entry.record = Record(receiver: receiver, ghostUserId: ghostUserId, receiverCheckedAt: now())
        entry.profile = ReadSchedule()
        setState(.unknown, of: spaceId)
        return true
    }

    /// One search for the receiver and the ghost in the direct chats of the
    /// space, in the limits of step 1.
    private func searchGhost(of spaceId: String, entry: inout Progress, from source: Source) async -> Search {
        guard entry.stateReads < Self.maxStateReads, entry.emptySearches < Self.maxEmptySearches,
              entry.search.isDue(at: now(), refreshInterval: 0, maxFailedReads: 1, backOff: Self.retryInterval)
        else { return .skipped }

        let candidates = await source.candidates(spaceId, entry.answeredRooms, Self.maxStateReads - entry.stateReads)
        if candidates.isEmpty {
            entry.emptySearches += 1
        }
        var failed = false
        for candidate in candidates.prefix(Self.maxStateReads - entry.stateReads) {
            entry.stateReads += 1
            do {
                let roomState = try await source.fetchState(candidate.roomId)
                entry.answeredRooms.insert(candidate.roomId)
                guard let receiver = try BridgeInfo.receiver(roomState: roomState) else { continue }
                let ghost = candidate.peerUserIds.lazy.compactMap { peer in
                    OwnServiceGhost.userId(receiver: receiver, peerUserId: peer, accountUserId: source.accountUserId)
                }.first
                guard let ghost else { continue }
                // This chat gave the ghost: a later receiver check reads it
                // again.
                entry.answeredRooms.remove(candidate.roomId)
                return .found(receiver: receiver, ghostUserId: ghost)
            } catch {
                failed = true
                source.report("failed to read the bridge info for \(spaceId): \(Self.name(of: error))")
            }
        }
        entry.search.recordFailure(at: now())
        return .noGhost(failed: failed)
    }

    /// Step 2: see the rules on the type.
    ///
    /// - Returns: whether the read failed with `ProfileNotFound`.
    @discardableResult
    private func readProfile(of spaceId: String, from source: Source) async -> Bool {
        guard var entry = progress[spaceId], var record = entry.record else { return false }
        defer { progress[spaceId] = entry }
        let isDue = entry.profile.isDue(
            at: now(),
            refreshInterval: Self.profileRefreshInterval,
            maxFailedReads: Self.maxFailedReads,
            backOff: Self.retryInterval
        )
        guard isDue else { return false }
        do {
            let url = try await source.fetchAvatarUrl(record.ghostUserId)
            record.avatarUrl = url.flatMap { $0.isEmpty ? nil : $0 }
            record.profileReadAt = now()
            entry.record = record
            entry.profile.recordSuccess(at: now())
            setState(.resolved(avatarUrl: record.avatarUrl), of: spaceId)
            writeCache(record, of: spaceId, from: source)
            return false
        } catch {
            entry.profile.recordFailure(at: now())
            source.report("failed to read the own service profile for \(spaceId): \(Self.name(of: error))")
            if record.profileReadAt == nil {
                setState(.failed, of: spaceId)
                // The ghost is kept, so the state read does not run again.
                writeCache(record, of: spaceId, from: source)
            }
            return error is ProfileNotFound
        }
    }

    private func setState(_ state: State, of spaceId: String) {
        if stateBySpace[spaceId] != state {
            stateBySpace[spaceId] = state
        }
    }

    /// A short name for an error, safe for the log. Never the description,
    /// which can hold a URL.
    private nonisolated static func name(of error: Error) -> String {
        if error is BridgeInfo.MalformedRoomState {
            return "the room state is not a JSON array of events"
        }
        return RoomStateReader.logName(of: error)
    }
}

// MARK: - Cache file

extension OwnServiceAvatarStore {
    private struct CacheFile: Codable {
        var version = 1
        let record: Record
    }

    /// The cache file of a space: `<directory>/<percent-encoded space ID>.json`.
    public nonisolated static func cacheFile(for spaceId: String, in directory: URL) -> URL {
        let name = spaceId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "space"
        return directory.appending(component: "\(name).json")
    }

    private func readCache(of spaceId: String, from source: Source) async {
        guard let directory = source.cacheDirectory,
              var record = await Self.readCache(at: Self.cacheFile(for: spaceId, in: directory))?.record,
              progress[spaceId]?.record == nil,
              record.ghostUserId.hasPrefix("@"),
              record.ghostUserId.lowercased() != source.accountUserId.lowercased()
        else { return }
        // A time after now is not a time of a read: read the profile again.
        if let readAt = record.profileReadAt, readAt > now() {
            record.profileReadAt = nil
        }
        var entry = progress[spaceId] ?? Progress()
        entry.record = record
        entry.profile = ReadSchedule(lastGoodRead: record.profileReadAt)
        progress[spaceId] = entry
        if record.profileReadAt != nil {
            setState(.resolved(avatarUrl: record.avatarUrl), of: spaceId)
        }
    }

    /// Writes the record of a space. A newer write waits for the older one,
    /// so the file ends with the newest record.
    private func writeCache(_ record: Record, of spaceId: String, from source: Source) {
        guard let directory = source.cacheDirectory else { return }
        let file = Self.cacheFile(for: spaceId, in: directory)
        let earlier = cacheWrites[spaceId]
        let write = Task {
            await earlier?.value
            if let problem = await Self.write(CacheFile(record: record), to: file) {
                source.report("failed to write the own service profile cache of \(spaceId): \(problem)")
            }
        }
        cacheWrites[spaceId] = write
    }

    private nonisolated static func readCache(at url: URL) async -> CacheFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheFile.self, from: data)
    }

    /// - Returns: nil, or what went wrong.
    private nonisolated static func write(_ file: CacheFile, to url: URL) async -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(file).write(to: url, options: .atomic)
            return nil
        } catch {
            return RoomStateReader.logName(of: error)
        }
    }
}
