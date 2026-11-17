import Foundation
import Models
import Testing

/// MATRIX-171: the receiver check of a kept ghost, and the rooms of the
/// candidate search. The clock and every source are stubs.
@MainActor
struct OwnServiceReceiverCheckTests: OwnServiceStoreFixture {
    private static let newReceiver = "T1C6G4L3C-U2NEWLOGIN"
    private static let newGhost = "@slack_t1c6g4l3c-u2newlogin:davlin.io"
    private static let newAvatar = "mxc://davlin.io/new-login"

    private func logInAgain(_ backend: OwnServiceBackend) {
        backend.states[Self.chat(1).roomId] = .success(Self.bridgeState(receiver: Self.newReceiver))
        backend.avatars[Self.newGhost] = .success(Self.newAvatar)
    }

    // MARK: - The rule

    @Test func aCheckIsDueAfterAWeek() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let week = OwnServiceReceiverCheck.interval
        #expect(week == 7 * 24 * 60 * 60)
        #expect(!OwnServiceReceiverCheck.isDue(lastCheck: now, now: now, profileNotFound: false))
        #expect(!OwnServiceReceiverCheck.isDue(lastCheck: now - week + 1, now: now, profileNotFound: false))
        #expect(OwnServiceReceiverCheck.isDue(lastCheck: now - week, now: now, profileNotFound: false))
        // A file with no time of a check, and a time after now.
        #expect(OwnServiceReceiverCheck.isDue(lastCheck: nil, now: now, profileNotFound: false))
        #expect(OwnServiceReceiverCheck.isDue(lastCheck: now + 60, now: now, profileNotFound: false))
    }

    @Test func aProfileThatIsNotFoundDoesNotWaitForTheWeek() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        #expect(OwnServiceReceiverCheck.isDue(lastCheck: now, now: now, profileNotFound: true))
    }

    @Test func onlyAChangedReceiverReplacesTheGhost() {
        #expect(!OwnServiceReceiverCheck.replacesGhost(cachedReceiver: "T1-U1", liveReceiver: "T1-U1"))
        #expect(!OwnServiceReceiverCheck.replacesGhost(cachedReceiver: "T1-U1", liveReceiver: "t1-u1"))
        #expect(OwnServiceReceiverCheck.replacesGhost(cachedReceiver: "T1-U1", liveReceiver: "T1-U2"))
    }

    // MARK: - The weekly check in the store

    @Test func aNewLoginReplacesTheGhostAfterAWeek() async throws {
        let backend = try makeBackend(cache: true)
        defer { removeCache(backend) }
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)

        logInAgain(backend)
        clock.advance(by: OwnServiceReceiverCheck.interval - 1)
        await store.load(roomId: Self.channel, from: backend.source)
        // Not a week yet: the profile of the old ghost only.
        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads == [Self.ghost, Self.ghost])

        clock.advance(by: 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads == [Self.chat(1).roomId, Self.chat(1).roomId])
        #expect(backend.profileReads.last == Self.newGhost)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.newAvatar)

        // The cache file holds the new ghost.
        await store.waitForCacheWrites()
        let next = OwnServiceAvatarStore(now: { clock.time })
        await next.load(roomId: Self.channel, from: backend.source)
        #expect(next.avatarUrl(forRoom: Self.channel) == Self.newAvatar)
        #expect(backend.stateReads.count == 2)
    }

    @Test func theSameReceiverKeepsTheGhostAndWaitsAnotherWeek() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)

        clock.advance(by: OwnServiceReceiverCheck.interval)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads.count == 2)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)

        // The week starts again at the check.
        clock.advance(by: OwnServiceReceiverCheck.interval - 1)
        await store.load(roomId: Self.channel, from: backend.source)
        #expect(backend.stateReads.count == 2)
        #expect(backend.profileReads.allSatisfy { $0 == Self.ghost })
    }

    @Test func aCheckThatGivesNoReceiverKeepsTheGhost() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)

        backend.states[Self.chat(1).roomId] = .failure(OwnServiceReadFailed())
        clock.advance(by: OwnServiceReceiverCheck.interval)
        await store.load(roomId: Self.channel, from: backend.source)
        await store.load(roomId: Self.channel, from: backend.source)

        // One failed read, then the wait of step 1. The image stays.
        #expect(backend.stateReads.count == 2)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
        #expect(store.state(ofSpace: Self.space) == .resolved(avatarUrl: Self.ghostAvatar))
    }

    @Test func aCacheFileWithNoCheckTimeIsCheckedAtOnce() async throws {
        let backend = try makeBackend(cache: true)
        defer { removeCache(backend) }
        logInAgain(backend)
        let clock = PackStoreClock()
        let directory = try #require(backend.cacheDirectory)
        // A file of MATRIX-165, with a fresh profile read.
        let record = """
        {"version": 1, "record": {"receiver": "T1C6G4L3C-U1CCDGWMD", "ghostUserId": "\(Self.ghost)", \
        "avatarUrl": "\(Self.ghostAvatar)", "profileReadAt": \(clock.time.timeIntervalSinceReferenceDate)}}
        """
        try Data(record.utf8).write(to: OwnServiceAvatarStore.cacheFile(for: Self.space, in: directory))
        let store = OwnServiceAvatarStore(now: { clock.time })

        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads.count == 1)
        #expect(backend.profileReads == [Self.newGhost])
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.newAvatar)
    }

    // MARK: - The profile is not found

    @Test func aProfileThatIsNotFoundChecksTheReceiverAtOnce() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)

        // The new login removed the old ghost. A day later the profile read
        // is due, long before the week.
        logInAgain(backend)
        backend.avatars[Self.ghost] = .failure(OwnServiceAvatarStore.ProfileNotFound())
        clock.advance(by: OwnServiceAvatarStore.profileRefreshInterval)
        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads.count == 2)
        #expect(backend.profileReads == [Self.ghost, Self.ghost, Self.newGhost])
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.newAvatar)
    }

    @Test func aProfileThatIsNotFoundChecksOneTimePerSession() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)

        // Not found, and the receiver is the same: the ghost stays.
        backend.avatars[Self.ghost] = .failure(OwnServiceAvatarStore.ProfileNotFound())
        clock.advance(by: OwnServiceAvatarStore.profileRefreshInterval)
        for _ in 0 ..< 3 {
            await store.load(roomId: Self.channel, from: backend.source)
        }

        #expect(backend.stateReads.count == 2)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
    }

    @Test func aFailedProfileReadThatIsNotNotFoundChecksNothing() async throws {
        let backend = try makeBackend()
        let clock = PackStoreClock()
        let store = OwnServiceAvatarStore(now: { clock.time })
        await store.load(roomId: Self.channel, from: backend.source)

        logInAgain(backend)
        backend.avatars[Self.ghost] = .failure(OwnServiceReadFailed())
        clock.advance(by: OwnServiceAvatarStore.profileRefreshInterval)
        await store.load(roomId: Self.channel, from: backend.source)

        #expect(backend.stateReads.count == 1)
        #expect(store.avatarUrl(forRoom: Self.channel) == Self.ghostAvatar)
    }

    // MARK: - The rooms of the candidate search

    private typealias Room = OwnServiceCandidateRooms.Room

    @Test func theSearchReadsTheUnfilteredListNotTheSidebar() {
        // The sidebar shows a filter that holds no direct chat of the
        // workspace.
        let sidebar = [Room(id: "!channel", isDirect: false)]
        let account = [
            Room(id: "!channel", isDirect: false),
            Room(id: "!dm2", isDirect: true),
            Room(id: "!dm1", isDirect: true),
        ]
        #expect(OwnServiceCandidateRooms.roomIds(account: account, sidebar: sidebar, excluding: []) == ["!dm2", "!dm1"])
    }

    @Test func theSidebarIsUsedOnlyWhenTheUnfilteredListIsEmpty() {
        let sidebar = [Room(id: "!dm1", isDirect: true), Room(id: "!channel", isDirect: false)]
        #expect(OwnServiceCandidateRooms.roomIds(account: [], sidebar: sidebar, excluding: []) == ["!dm1"])
        let account = [Room(id: "!dm9", isDirect: true)]
        #expect(OwnServiceCandidateRooms.roomIds(account: account, sidebar: sidebar, excluding: []) == ["!dm9"])
    }

    @Test func theSearchSkipsAnsweredRoomsAndKeepsRoomsWithNoInfo() {
        let account = [
            Room(id: "!answered", isDirect: true),
            Room(id: "!noInfo", isDirect: nil),
            Room(id: "!dm1", isDirect: true),
            Room(id: "!dm1", isDirect: true),
        ]
        let ids = OwnServiceCandidateRooms.roomIds(account: account, sidebar: [], excluding: ["!answered"])
        #expect(ids == ["!noInfo", "!dm1"])
    }
}
