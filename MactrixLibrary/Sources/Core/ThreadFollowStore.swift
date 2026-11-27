import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The two MSC4306 calls of one room, as closures, so the store runs in
/// tests (MATRIX-261).
///
/// Signatures (docs/ffi/matrix_sdk_ffi.swift): `Room.fetchThreadSubscription(
/// threadRootEventId:) async throws -> ThreadSubscription?` (line 10620) and
/// `Room.setThreadSubscription(threadRootEventId:subscribed:) async throws`
/// (line 11017). At the pinned SDK both send the request with no check of
/// the SDK's `/versions` cache, so they work as soon as the server has
/// MSC4306. A set with `subscribed: true` is a manual subscription.
public struct ThreadSubscriptionCalls: Sendable {
    let fetch: @Sendable (String) async throws -> ThreadSubscription?
    let set: @Sendable (String, Bool) async throws -> Void

    public init(room: any RoomProtocol) {
        fetch = { root in try await room.fetchThreadSubscription(threadRootEventId: root) }
        set = { root, subscribed in try await room.setThreadSubscription(threadRootEventId: root, subscribed: subscribed) }
    }

    init(
        fetch: @escaping @Sendable (String) async throws -> ThreadSubscription?,
        set: @escaping @Sendable (String, Bool) async throws -> Void
    ) {
        self.fetch = fetch
        self.set = set
    }
}

/// The thread follow state of the account on this device (MATRIX-261): the
/// server's MSC4306 support, the reads of the last seconds, and the roots
/// that the own-root rule must not act on again.
///
/// One store for the process, as `OwnReactionMarks`: the thread panel, the
/// room timelines, and the notification path share it. The support record
/// and the handled roots are kept in `UserDefaults` (event IDs and dates
/// only). The follow state itself is on the server: the SDK syncs it to the
/// other devices (MSC4308).
///
/// Every failure logs at info level and shows nothing: before the server has
/// MSC4306, a read returns nil and a change fails with `M_UNRECOGNIZED`.
@MainActor
public final class ThreadFollowStore {
    public static let shared = ThreadFollowStore()

    private let defaults: UserDefaults
    private let supportKey: String
    private let handledKey: String
    private let now: () -> Date

    private var record: ThreadSubscriptionSupportRecord
    private var handled: ThreadFollowHandledRoots
    private var cache = ThreadFollowCache()
    private var ownRootsInFlight: Set<String> = []

    /// The calls of a room, by room ID, for the notification path. Nil before
    /// `configure` and after the sign-out: the banner filter then does
    /// nothing.
    private var callsForRoom: ((String) -> ThreadSubscriptionCalls?)?
    /// `Client.resetSupportedVersions()`.
    private var resetVersions: (@Sendable () async throws -> Void)?

    /// Who asks for a change.
    enum ChangeCause {
        /// Patrick, with the Follow control.
        case person
        /// The own-root rule.
        case ownRootRule
    }

    init(defaults: UserDefaults = .standard, keyPrefix: String = "threadFollow", now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        supportKey = "\(keyPrefix).support"
        handledKey = "\(keyPrefix).handledRoots"
        self.now = now
        record = Self.decode(ThreadSubscriptionSupportRecord.self, from: defaults.data(forKey: supportKey))
            ?? ThreadSubscriptionSupportRecord()
        handled = Self.decode(ThreadFollowHandledRoots.self, from: defaults.data(forKey: handledKey)) ?? ThreadFollowHandledRoots()
    }

    /// Gives the store the session's room lookup and version reset. Nil for
    /// both on the sign-out.
    func configure(
        callsForRoom: ((String) -> ThreadSubscriptionCalls?)?,
        resetVersions: (@Sendable () async throws -> Void)?
    ) {
        self.callsForRoom = callsForRoom
        self.resetVersions = resetVersions
    }

    /// Drops every record, for the sign-out.
    func removeAll() {
        record = ThreadSubscriptionSupportRecord()
        handled = ThreadFollowHandledRoots()
        cache = ThreadFollowCache()
        defaults.removeObject(forKey: supportKey)
        defaults.removeObject(forKey: handledKey)
    }

    /// The server's MSC4306 support now.
    public var support: ThreadSubscriptionSupport {
        record.support(at: now())
    }

    func isHandled(_ root: String) -> Bool {
        handled.contains(root)
    }

    // MARK: Read and change

    /// Reads the subscription of `root` from the server.
    func read(_ root: String, with calls: ThreadSubscriptionCalls) async -> ThreadFollowRead {
        do {
            let subscription = try await calls.fetch(root)
            let isFollowed = subscription != nil
            if isFollowed {
                await note(.subscriptionRead)
            }
            cache.store(isFollowed: isFollowed, root: root, at: now())
            return isFollowed ? .followed : .notFollowed
        } catch {
            Logger.threadFollow.info("read of thread \(root, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }

    /// Follows or unfollows `root`.
    ///
    /// A change by Patrick marks the root as handled before the call, so the
    /// own-root rule never undoes it, even when the call fails. A change by
    /// the rule marks it only when the server accepts it.
    ///
    /// - Returns: true if the server accepted the change.
    @discardableResult
    func change(_ root: String, follow: Bool, with calls: ThreadSubscriptionCalls, cause: ChangeCause) async -> Bool {
        if cause == .person {
            markHandled(root)
        }
        do {
            try await calls.set(root, follow)
            await note(.changeAccepted)
            markHandled(root)
            cache.store(isFollowed: follow, root: root, at: now())
            return true
        } catch {
            cache.remove(root: root)
            if let evidence = Self.evidence(for: error) {
                await note(evidence)
            }
            let verb = follow ? "follow" : "unfollow"
            Logger.threadFollow.info(
                "\(verb, privacy: .public) of thread \(root, privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            return false
        }
    }

    /// The evidence in a failed change: `M_UNRECOGNIZED` is the answer of a
    /// server that does not know the MSC4306 endpoint. Any other error (a
    /// network error, `M_NOT_FOUND` for an unknown root) tells nothing.
    nonisolated static func evidence(for error: Error) -> ThreadSubscriptionEvidence? {
        guard case let .MatrixApi(kind, code, _, _) = error as? ClientError else { return nil }
        return kind == .unrecognized || code == "M_UNRECOGNIZED" ? .endpointUnrecognized : nil
    }

    // MARK: Banner filter

    /// Whether a notification of `roomId` shows a banner (`ThreadBannerRule`).
    ///
    /// Cost: no read for an event in no thread, for a mention, or while the
    /// server's support is not known. Else one read for each thread for each
    /// `ThreadFollowCache.lifetime`.
    public func bannerShows(roomId: String, threadRoot: String?, hasMention: Bool?) async -> Bool {
        let cached = threadRoot.map { cache.read(root: $0, at: now()) } ?? .notRead
        var decision = ThreadBannerRule.decide(threadRoot: threadRoot, hasMention: hasMention, support: support, read: cached)
        if decision == .readFollowState, let threadRoot {
            guard let calls = callsForRoom?(roomId) else { return true }
            let read = await read(threadRoot, with: calls)
            decision = ThreadBannerRule.decide(threadRoot: threadRoot, hasMention: hasMention, support: support, read: read)
        }
        return decision != .drop
    }

    // MARK: Own root rule

    /// The first reply to the own message `root` arrived (`OwnRootReplyWatch`):
    /// applies `OwnRootFollowRule`.
    func firstReplyArrived(toOwnRoot root: String, with calls: ThreadSubscriptionCalls) async {
        guard ownRootsInFlight.insert(root).inserted else { return }
        defer { ownRootsInFlight.remove(root) }

        var decision = OwnRootFollowRule.decide(support: support, isHandled: isHandled(root), read: .notRead)
        if decision == .readFollowState {
            // A fresh read, not the cache: the rule writes.
            let read = await read(root, with: calls)
            decision = OwnRootFollowRule.decide(support: support, isHandled: isHandled(root), read: read)
        }
        switch decision {
        case .follow:
            if await change(root, follow: true, with: calls, cause: .ownRootRule) {
                Logger.threadFollow.info("followed the thread of own message \(root, privacy: .public) at its first reply")
            }
        case .skip(.alreadyFollowed):
            markHandled(root)
        case let .skip(reason):
            Logger.threadFollow.debug("own-root rule skipped \(root, privacy: .public): \(String(describing: reason), privacy: .public)")
        case .readFollowState:
            break
        }
    }

    // MARK: Records

    private func markHandled(_ root: String) {
        guard handled.insert(root) else { return }
        save(handled, key: handledKey)
    }

    /// Records evidence, and resets the SDK's `/versions` cache when the
    /// record asks for it (`ThreadSubscriptionSupportRecord.record`).
    private func note(_ evidence: ThreadSubscriptionEvidence) async {
        let resets = record.record(evidence, at: now())
        save(record, key: supportKey)
        guard resets else { return }
        guard let resetVersions else {
            // No session: the next evidence asks again.
            record.versionsResetFailed()
            save(record, key: supportKey)
            return
        }
        Logger.threadFollow.info("the server handles MSC4306: one reset of the SDK's /versions cache, for the next launch")
        do {
            try await resetVersions()
        } catch {
            Logger.threadFollow.info("reset of the SDK's /versions cache failed: \(String(describing: error), privacy: .public)")
            record.versionsResetFailed()
            save(record, key: supportKey)
        }
    }

    private func save(_ value: some Encodable, key: String) {
        do {
            try defaults.set(JSONEncoder().encode(value), forKey: key)
        } catch {
            Logger.threadFollow.error("thread follow: save of \(key, privacy: .public) failed: \(error)")
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The Follow control of one thread (MATRIX-261): the Mac thread panel
/// header and the iOS thread screen draw `control`, and a click calls
/// `toggle()`.
@MainActor @Observable
public final class ThreadFollowModel {
    public private(set) var state: ThreadFollowState = .reading

    @ObservationIgnored private let rootEventId: String
    @ObservationIgnored private let calls: ThreadSubscriptionCalls
    @ObservationIgnored private let store: ThreadFollowStore

    public convenience init(room: any RoomProtocol, rootEventId: String) {
        self.init(calls: ThreadSubscriptionCalls(room: room), rootEventId: rootEventId, store: .shared)
    }

    init(calls: ThreadSubscriptionCalls, rootEventId: String, store: ThreadFollowStore) {
        self.calls = calls
        self.rootEventId = rootEventId
        self.store = store
    }

    public var control: ThreadFollowControl {
        ThreadFollowControl(state: state)
    }

    /// Reads the state from the server. Call it when the thread opens.
    public func load() async {
        state = await ThreadFollowState(read: store.read(rootEventId, with: calls))
    }

    /// Asks the server for the other state, then reads the state again.
    public func toggle() async {
        let control = control
        guard control.isEnabled else { return }
        state = .changing(toFollowed: control.follows)
        await store.change(rootEventId, follow: control.follows, with: calls, cause: .person)
        await load()
    }
}
