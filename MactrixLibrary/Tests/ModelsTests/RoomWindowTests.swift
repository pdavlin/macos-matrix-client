import Foundation
import Models
import Testing

/// MATRIX-116: what a single-room window shows.
struct RoomWindowPhaseTests {
    private func phase(
        _ session: RoomWindowSession,
        loaded: Bool = true,
        _ room: RoomWindowRoomLookup = .notFound
    ) -> RoomWindowPhase {
        RoomWindowPhase.resolve(session: session, roomListLoaded: loaded, room: room)
    }

    @Test func waitsForTheSessionRestoreBeforeItLooksUpTheRoom() {
        #expect(phase(.restoring, loaded: false, .notFound) == .waitingForSession)
        // Even a room the lookup somehow holds waits: no client, no timeline.
        #expect(phase(.restoring, loaded: true, .found(.joined)) == .waitingForSession)
    }

    @Test func noSessionIsSignedOut() {
        #expect(phase(.signedOut, loaded: false, .notFound) == .unavailable(.signedOut))
        #expect(phase(.signedOut, loaded: true, .found(.joined)) == .unavailable(.signedOut))
    }

    @Test func aMissingRoomIsStillLoadingUntilTheRoomListLoads() {
        #expect(phase(.signedIn, loaded: false, .notFound) == .lookingUpRoom)
        #expect(phase(.signedIn, loaded: true, .notFound) == .unavailable(.notInRoomList))
    }

    @Test func joinedInvitedAndKnockedRoomsShow() {
        for membership in [Membership.joined, .invited, .knocked] {
            #expect(phase(.signedIn, loaded: false, .found(membership)) == .showingRoom)
            #expect(phase(.signedIn, loaded: true, .found(membership)) == .showingRoom)
        }
    }

    @Test func aLeftOrKickedRoomIsUnavailable() {
        #expect(phase(.signedIn, .found(.left)) == .unavailable(.left))
        #expect(phase(.signedIn, .found(.banned)) == .unavailable(.banned))
    }

    @Test func theRoomComesBackWhenItsInputsComeBack() {
        // Leave, then rejoin.
        #expect(phase(.signedIn, .found(.left)) == .unavailable(.left))
        #expect(phase(.signedIn, .found(.joined)) == .showingRoom)
        // Sign out, then sign in again.
        #expect(phase(.signedOut, .found(.joined)) == .unavailable(.signedOut))
        #expect(phase(.signedIn, .found(.joined)) == .showingRoom)
    }

    @Test func onlyTheShowingPhaseKeepsATimeline() {
        #expect(RoomWindowPhase.showingRoom.keepsTimeline)
        #expect(!RoomWindowPhase.waitingForSession.keepsTimeline)
        #expect(!RoomWindowPhase.lookingUpRoom.keepsTimeline)
        #expect(!RoomWindowPhase.unavailable(.signedOut).keepsTimeline)
        #expect(!RoomWindowPhase.unavailable(.left).keepsTimeline)
    }
}

/// MATRIX-116: the restoration value of a room window.
struct RoomWindowIDTests {
    @Test func roundTripsThroughCodable() throws {
        let id = RoomWindowID(roomId: "!general:example.org")
        let data = try JSONEncoder().encode(id)
        #expect(try JSONDecoder().decode(RoomWindowID.self, from: data) == id)
    }

    @Test func theCodedFormIsStable() throws {
        // A changed shape would drop every saved room window on relaunch.
        let data = Data(#"{"roomId":"!general:example.org"}"#.utf8)
        let decoded = try JSONDecoder().decode(RoomWindowID.self, from: data)
        #expect(decoded == RoomWindowID(roomId: "!general:example.org"))
    }
}

/// MATRIX-116: the main window's sidebar width across launches.
struct SidebarWidthMemoryTests {
    @Test func startsAtTheDefaultWithNothingStored() {
        #expect(SidebarWidthMemory.idealWidth(stored: nil, minimum: 300, defaultIdeal: 380) == 380)
        #expect(SidebarWidthMemory.idealWidth(stored: 0, minimum: 300, defaultIdeal: 380) == 380)
        #expect(SidebarWidthMemory.idealWidth(stored: .nan, minimum: 300, defaultIdeal: 380) == 380)
    }

    @Test func startsAtTheStoredWidthButNeverBelowTheMinimum() {
        #expect(SidebarWidthMemory.idealWidth(stored: 450, minimum: 300, defaultIdeal: 380) == 450)
        #expect(SidebarWidthMemory.idealWidth(stored: 120, minimum: 300, defaultIdeal: 380) == 300)
    }

    @Test func storesWholePointsAndSkipsUnchangedWidths() {
        #expect(SidebarWidthMemory.widthToStore(measured: 412.4, minimum: 300, current: nil) == 412)
        #expect(SidebarWidthMemory.widthToStore(measured: 412.4, minimum: 300, current: 412) == nil)
        #expect(SidebarWidthMemory.widthToStore(measured: 413, minimum: 300, current: 412) == 413)
    }

    @Test func doesNotStoreACollapsedOrAnimatingColumn() {
        #expect(SidebarWidthMemory.widthToStore(measured: 0, minimum: 300, current: 412) == nil)
        #expect(SidebarWidthMemory.widthToStore(measured: 180, minimum: 300, current: 412) == nil)
        #expect(SidebarWidthMemory.widthToStore(measured: .infinity, minimum: 300, current: 412) == nil)
    }
}
