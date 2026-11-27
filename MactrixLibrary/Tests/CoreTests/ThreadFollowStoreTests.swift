@testable import Core
import Foundation
import MatrixRustSDK
import Models
import Testing

/// A homeserver for the two MSC4306 calls, with or without MSC4306.
private actor FakeThreadServer {
    var handlesMSC4306: Bool
    private(set) var subscribed: Set<String> = []
    private(set) var fetches = 0
    private(set) var sets: [(root: String, subscribed: Bool)] = []

    init(handlesMSC4306: Bool, subscribed: Set<String> = []) {
        self.handlesMSC4306 = handlesMSC4306
        self.subscribed = subscribed
    }

    func fetch(_ root: String) -> ThreadSubscription? {
        fetches += 1
        return handlesMSC4306 && subscribed.contains(root) ? ThreadSubscription(automatic: false) : nil
    }

    func set(_ root: String, _ subscribe: Bool) throws {
        sets.append((root, subscribe))
        guard handlesMSC4306 else {
            throw ClientError.MatrixApi(kind: .unrecognized, code: "M_UNRECOGNIZED", msg: "Unrecognized request", details: nil)
        }
        if subscribe {
            subscribed.insert(root)
        } else {
            subscribed.remove(root)
        }
    }

    func setHandlesMSC4306(_ value: Bool) {
        handlesMSC4306 = value
    }

    nonisolated var calls: ThreadSubscriptionCalls {
        ThreadSubscriptionCalls(
            fetch: { root in await self.fetch(root) },
            set: { root, subscribe in try await self.set(root, subscribe) }
        )
    }
}

/// Counts the calls of `Client.resetSupportedVersions()`.
@MainActor
private final class ResetCounter {
    var count = 0
}

/// MATRIX-261: the store over the two SDK calls: the reset-once rule, the
/// banner filter, the own-root rule, and the control.
@MainActor
struct ThreadFollowStoreTests {
    private let resets = ResetCounter()

    private func store(suite: String, server: FakeThreadServer) throws -> ThreadFollowStore {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let store = ThreadFollowStore(defaults: defaults)
        let resets = resets
        store.configure(
            callsForRoom: { _ in server.calls },
            resetVersions: { await MainActor.run { resets.count += 1 } }
        )
        return store
    }

    // MARK: Server without MSC4306

    /// Today's server: the control reads off, a click fails quietly, and the
    /// banners keep showing with no read.
    @Test func serverWithoutMSC4306IsQuiet() async throws {
        let server = FakeThreadServer(handlesMSC4306: false)
        let store = try store(suite: "ThreadFollowStoreTests.without", server: server)
        let model = ThreadFollowModel(calls: server.calls, rootEventId: "$root", store: store)

        await model.load()
        #expect(model.state == .notFollowed)
        #expect(store.support == .unknown)

        await model.toggle()
        #expect(model.state == .notFollowed)
        #expect(store.support == .unsupported)
        #expect(resets.count == 0)

        let fetchesBefore = await server.fetches
        #expect(await store.bannerShows(roomId: "!r", threadRoot: "$other", hasMention: false))
        #expect(await server.fetches == fetchesBefore)

        await store.firstReplyArrived(toOwnRoot: "$mine", with: server.calls)
        #expect(await server.sets.count == 1)
    }

    // MARK: Reset once

    @Test func firstSupportResetsTheVersionsCacheOnce() async throws {
        let server = FakeThreadServer(handlesMSC4306: true)
        let store = try store(suite: "ThreadFollowStoreTests.reset", server: server)

        #expect(await store.change("$a", follow: true, with: server.calls, cause: .person))
        #expect(resets.count == 1)
        #expect(await store.read("$a", with: server.calls) == .followed)
        #expect(await store.change("$a", follow: false, with: server.calls, cause: .person))
        #expect(resets.count == 1)
    }

    /// A read with no subscription is no evidence: the server without MSC4306
    /// gives the same answer. So the reset does not run while the flag is off.
    @Test func emptyReadsDoNotReset() async throws {
        let server = FakeThreadServer(handlesMSC4306: false)
        let store = try store(suite: "ThreadFollowStoreTests.emptyReads", server: server)
        for root in ["$a", "$b", "$c"] {
            #expect(await store.read(root, with: server.calls) == .notFollowed)
        }
        #expect(resets.count == 0)
        #expect(store.support == .unknown)

        // The flag goes on: the first accepted change resets.
        await server.setHandlesMSC4306(true)
        #expect(await store.change("$a", follow: true, with: server.calls, cause: .person))
        #expect(resets.count == 1)
        #expect(store.support == .supported)
    }

    // MARK: Banner filter

    @Test func bannerFollowsTheThreadState() async throws {
        let server = FakeThreadServer(handlesMSC4306: true, subscribed: ["$followed"])
        let store = try store(suite: "ThreadFollowStoreTests.banner", server: server)
        _ = await store.read("$followed", with: server.calls)
        #expect(store.support == .supported)

        #expect(await store.bannerShows(roomId: "!r", threadRoot: "$followed", hasMention: false))
        #expect(await !(store.bannerShows(roomId: "!r", threadRoot: "$quiet", hasMention: false)))
        // A mention shows, and needs no read.
        let fetches = await server.fetches
        #expect(await store.bannerShows(roomId: "!r", threadRoot: "$other", hasMention: true))
        // No thread: no read.
        #expect(await store.bannerShows(roomId: "!r", threadRoot: nil, hasMention: false))
        #expect(await server.fetches == fetches)
    }

    /// A burst in one thread reads once, and a change with the control
    /// applies at once.
    @Test func bannerUsesTheCacheAndTheControlUpdatesIt() async throws {
        let server = FakeThreadServer(handlesMSC4306: true, subscribed: ["$t", "$seen"])
        let store = try store(suite: "ThreadFollowStoreTests.cache", server: server)
        _ = await store.read("$seen", with: server.calls)
        let fetchesBefore = await server.fetches

        #expect(await store.bannerShows(roomId: "!r", threadRoot: "$t", hasMention: false) == true)
        let fetches = await server.fetches
        #expect(fetches == fetchesBefore + 1)
        #expect(await store.bannerShows(roomId: "!r", threadRoot: "$t", hasMention: false) == true)
        #expect(await server.fetches == fetches)

        #expect(await store.change("$t", follow: false, with: server.calls, cause: .person))
        #expect(await !(store.bannerShows(roomId: "!r", threadRoot: "$t", hasMention: false)))
        #expect(await server.fetches == fetches)
    }

    // MARK: Own root rule

    @Test func firstReplyFollowsTheOwnRootOnce() async throws {
        let server = FakeThreadServer(handlesMSC4306: true, subscribed: ["$seen"])
        let store = try store(suite: "ThreadFollowStoreTests.ownRoot", server: server)
        _ = await store.read("$seen", with: server.calls)

        await store.firstReplyArrived(toOwnRoot: "$mine", with: server.calls)
        #expect(await server.sets.map(\.root) == ["$mine"])
        #expect(await server.sets.map(\.subscribed) == [true])

        // Patrick unfollows later: a second arrival does not follow again.
        #expect(await store.change("$mine", follow: false, with: server.calls, cause: .person))
        await store.firstReplyArrived(toOwnRoot: "$mine", with: server.calls)
        #expect(await server.sets.map(\.subscribed) == [true, false])
    }

    @Test func alreadyFollowedRootIsNotSetAgain() async throws {
        let server = FakeThreadServer(handlesMSC4306: true, subscribed: ["$mine"])
        let store = try store(suite: "ThreadFollowStoreTests.alreadyFollowed", server: server)
        _ = await store.read("$mine", with: server.calls)

        await store.firstReplyArrived(toOwnRoot: "$mine", with: server.calls)
        #expect(await server.sets.isEmpty)
        #expect(store.isHandled("$mine"))
    }

    /// An Unfollow on this device before the first reply holds, even if the
    /// change failed (no network).
    @Test func alreadyUnfollowedRootIsNotFollowed() async throws {
        let server = FakeThreadServer(handlesMSC4306: true, subscribed: ["$seen"])
        let store = try store(suite: "ThreadFollowStoreTests.alreadyUnfollowed", server: server)
        _ = await store.read("$seen", with: server.calls)
        #expect(await store.change("$mine", follow: false, with: server.calls, cause: .person))
        let fetches = await server.fetches

        await store.firstReplyArrived(toOwnRoot: "$mine", with: server.calls)
        #expect(await server.sets.map(\.subscribed) == [false])
        #expect(await server.fetches == fetches)
    }

    // MARK: Control

    @Test func controlFollowsAndUnfollows() async throws {
        let server = FakeThreadServer(handlesMSC4306: true)
        let store = try store(suite: "ThreadFollowStoreTests.control", server: server)
        let model = ThreadFollowModel(calls: server.calls, rootEventId: "$root", store: store)
        #expect(model.state == .reading)

        await model.load()
        #expect(model.state == .notFollowed)
        await model.toggle()
        #expect(model.state == .followed)
        await model.toggle()
        #expect(model.state == .notFollowed)
        #expect(await server.sets.map(\.subscribed) == [true, false])
    }

    // MARK: Error mapping

    @Test func onlyUnrecognizedIsEvidence() {
        let unrecognized = ClientError.MatrixApi(kind: .unrecognized, code: "M_UNRECOGNIZED", msg: "", details: nil)
        let notFound = ClientError.MatrixApi(kind: .notFound, code: "M_NOT_FOUND", msg: "", details: nil)
        let network = ClientError.Generic(msg: "offline", details: nil)
        #expect(ThreadFollowStore.evidence(for: unrecognized) == .endpointUnrecognized)
        #expect(ThreadFollowStore.evidence(for: notFound) == nil)
        #expect(ThreadFollowStore.evidence(for: network) == nil)
    }
}
