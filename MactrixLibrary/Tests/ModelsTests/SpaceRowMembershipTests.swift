import Models
import Testing

/// MATRIX-121: a joined space must never offer "Join", even when the inbox
/// room list (which holds no spaces) and `getRoom` do not know it.
struct SpaceRowMembershipTests {
    @Test
    func hierarchyStateAloneMeansJoined() {
        #expect(SpaceRowMembership.isJoined(hierarchyStateIsJoined: true, isInRoomList: false, clientReportsJoined: false))
    }

    @Test
    func roomListAloneMeansJoined() {
        #expect(SpaceRowMembership.isJoined(hierarchyStateIsJoined: false, isInRoomList: true, clientReportsJoined: false))
    }

    @Test
    func clientAloneMeansJoined() {
        #expect(SpaceRowMembership.isJoined(hierarchyStateIsJoined: false, isInRoomList: false, clientReportsJoined: true))
    }

    @Test
    func noSourceMeansNotJoined() {
        #expect(!SpaceRowMembership.isJoined(hierarchyStateIsJoined: false, isInRoomList: false, clientReportsJoined: false))
    }
}
