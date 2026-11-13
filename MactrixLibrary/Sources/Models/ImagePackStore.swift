import Foundation

/// The image packs of the spaces that hold the open chats (MATRIX-155).
///
/// A bridge puts each chat of a Slack workspace in the workspace's space, and
/// writes the workspace's custom emoji into that space's state. For a room,
/// the store finds the parent spaces, then loads each space's packs: first
/// from one JSON cache file per space, then from the homeserver. The store
/// has no SDK and no network of its own: `Source` gives it the parent lookup,
/// the state read (`ImagePackStateReader`), and the cache folder, so tests run
/// from fixtures.
///
/// Rules:
/// - The homeserver read runs at most once per space per app session, plus
///   once for each call with `refresh`. A read that fails does not count,
///   but a space gets at most `maxFailedReads` failed reads per session.
/// - A read that fails is reported and leaves the packs in use as they are.
/// - "No parent space" is not kept: the SDK gives that answer until its space
///   graph is ready (`RoomAccountNames`), so the next call asks again.
/// - The cache file holds the parsed packs only (shortcodes and `mxc://`
///   URIs), not the room state.
///
/// Usage (in `Core`):
/// ```swift
/// await store.load(roomId: room.id, from: source)
/// let packs = store.packs(forRoom: room.id)
/// ```
@MainActor @Observable
public final class ImagePackStore {
    /// A parent space of a room.
    public struct Space: Equatable, Sendable {
        public let id: String
        /// The space's name: the title of a pack that has no name.
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    /// What the store reads from.
    public struct Source {
        /// The folder of the cache files, or nil for no cache.
        public let cacheDirectory: URL?
        /// The joined parent spaces of a room.
        public let parentSpaces: @MainActor (_ roomId: String) async throws -> [Space]
        /// The state of a space, as `ImagePack.parse(roomState:)` reads it.
        public let fetchState: @MainActor (_ spaceId: String) async throws -> Data
        /// Takes one line for the log when a read fails. The line holds a
        /// room ID and an error name, never a token or a response body.
        public let report: @MainActor (String) -> Void

        public init(
            cacheDirectory: URL?,
            parentSpaces: @escaping @MainActor (_ roomId: String) async throws -> [Space],
            fetchState: @escaping @MainActor (_ spaceId: String) async throws -> Data,
            report: @escaping @MainActor (String) -> Void
        ) {
            self.cacheDirectory = cacheDirectory
            self.parentSpaces = parentSpaces
            self.fetchState = fetchState
            self.report = report
        }
    }

    /// The failed homeserver reads that one space gets per session.
    public static let maxFailedReads = 3

    /// The packs by space ID. A space that was read and has no pack has an
    /// empty list.
    public private(set) var packsBySpace: [String: [ImagePack]] = [:]
    /// The parent space IDs by room ID, for the rooms that have a parent.
    public private(set) var spacesByRoom: [String: [String]] = [:]

    @ObservationIgnored private var spaces: [String: Space] = [:]
    @ObservationIgnored private var resolvingRooms: Set<String> = []
    @ObservationIgnored private var cacheReadSpaces: Set<String> = []
    @ObservationIgnored private var fetchedSpaces: Set<String> = []
    @ObservationIgnored private var fetchingSpaces: Set<String> = []
    @ObservationIgnored private var failedReads: [String: Int] = [:]

    public init() {}

    /// The packs a reaction in `roomId` can use: the packs of the room's
    /// parent spaces. Empty until `load` found them, and for a room with no
    /// pack. The read is observable.
    public func packs(forRoom roomId: String) -> [ImagePack] {
        (spacesByRoom[roomId] ?? []).flatMap { packsBySpace[$0] ?? [] }
    }

    /// Loads the packs of the room's parent spaces. Safe to call on each
    /// chat open and each picker open: see the rules on the type.
    ///
    /// - Parameters:
    ///   - roomId: The room of the chat.
    ///   - refresh: Reads the parent spaces and the homeserver again.
    ///   - source: Where to read from.
    public func load(roomId: String, refresh: Bool = false, from source: Source) async {
        for space in await parentSpaces(of: roomId, refresh: refresh, from: source) {
            await loadPacks(of: space, refresh: refresh, from: source)
        }
    }

    private func parentSpaces(of roomId: String, refresh: Bool, from source: Source) async -> [Space] {
        if !refresh, let known = spacesByRoom[roomId] {
            return known.compactMap { spaces[$0] }
        }
        guard resolvingRooms.insert(roomId).inserted else { return [] }
        defer { resolvingRooms.remove(roomId) }
        do {
            let parents = try await source.parentSpaces(roomId)
            // An empty answer is not final: see the rules on the type.
            guard !parents.isEmpty else { return [] }
            for parent in parents {
                spaces[parent.id] = parent
            }
            let parentIds = parents.map(\.id)
            if spacesByRoom[roomId] != parentIds {
                spacesByRoom[roomId] = parentIds
            }
            return parents
        } catch {
            source.report("failed to read the parent spaces of \(roomId): \(String(describing: error))")
            return []
        }
    }

    private func loadPacks(of space: Space, refresh: Bool, from source: Source) async {
        let cacheFile = source.cacheDirectory.map { Self.cacheFile(for: space.id, in: $0) }
        if let cacheFile, cacheReadSpaces.insert(space.id).inserted {
            let cached = await Self.readCache(at: cacheFile)
            if let cached, packsBySpace[space.id] == nil {
                packsBySpace[space.id] = cached
            }
        }

        guard !fetchingSpaces.contains(space.id) else { return }
        if !refresh {
            guard !fetchedSpaces.contains(space.id), failedReads[space.id, default: 0] < Self.maxFailedReads else { return }
        }
        fetchingSpaces.insert(space.id)
        defer { fetchingSpaces.remove(space.id) }
        do {
            let state = try await source.fetchState(space.id)
            let packs = try ImagePack.parse(roomState: state).map { $0.named(fallback: space.name) }
            fetchedSpaces.insert(space.id)
            if packsBySpace[space.id] != packs {
                packsBySpace[space.id] = packs
            }
            if let cacheFile, let problem = await Self.writeCache(packs, to: cacheFile) {
                source.report("failed to write the image pack cache of \(space.id): \(problem)")
            }
        } catch {
            failedReads[space.id, default: 0] += 1
            source.report("failed to read the image packs of \(space.id): \(Self.name(of: error))")
        }
    }

    // MARK: - Cache file

    private struct CacheFile: Codable {
        var version = 1
        let packs: [ImagePack]
    }

    /// The cache file of a space: `<directory>/<percent-encoded space ID>.json`.
    public nonisolated static func cacheFile(for spaceId: String, in directory: URL) -> URL {
        let name = spaceId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "space"
        return directory.appending(component: "\(name).json")
    }

    private nonisolated static func readCache(at url: URL) async -> [ImagePack]? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data)
        else { return nil }
        return file.packs
    }

    /// - Returns: nil, or what went wrong.
    private nonisolated static func writeCache(_ packs: [ImagePack], to url: URL) async -> String? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(CacheFile(packs: packs)).write(to: url, options: .atomic)
            return nil
        } catch {
            return name(of: error)
        }
    }

    /// A short name for an error, safe for the log: the case of our own
    /// errors, else the error's domain and code. Never the description, which
    /// can hold a URL.
    private nonisolated static func name(of error: Error) -> String {
        switch error {
        case let failure as ImagePackStateReader.Failure:
            return String(describing: failure)
        case is ImagePack.MalformedRoomState:
            return "the room state is not a JSON array of events"
        default:
            let nsError = error as NSError
            return "\(nsError.domain) \(nsError.code)"
        }
    }
}
