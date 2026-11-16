import Foundation
import Models
import Testing

/// MATRIX-165: the receiver of a room's bridge info.
struct BridgeInfoTests {
    private static func roomState(_ events: String) -> Data {
        Data("[\(events)]".utf8)
    }

    private static func bridgeEvent(type: String, receiver: String?) -> String {
        let receiverField = receiver.map { ", \"fi.mau.receiver\": \"\($0)\"" } ?? ""
        return """
        {"type": "\(type)", "state_key": "davlin.io/slack", "sender": "@slackbot:davlin.io",
         "content": {"bridgebot": "@slackbot:davlin.io", "protocol": {"id": "slack"},
                     "network": {"id": "T1C6G4L3C"},
                     "channel": {"id": "T1C6G4L3C-D0123ABCD"\(receiverField)}}}
        """
    }

    private static let member = """
    {"type": "m.room.member", "state_key": "@a:davlin.io", "content": {"membership": "join"}}
    """

    @Test
    func readsTheReceiverOfTheBridgeEvent() throws {
        let state = Self.roomState([
            Self.member,
            Self.bridgeEvent(type: "m.bridge", receiver: "T1C6G4L3C-U1CCDGWMD"),
        ].joined(separator: ","))
        #expect(try BridgeInfo.receiver(roomState: state) == "T1C6G4L3C-U1CCDGWMD")
    }

    @Test
    func readsTheHalfShotEventWhenItIsTheOnlyOne() throws {
        let state = Self.roomState(Self.bridgeEvent(type: "uk.half-shot.bridge", receiver: "T1C6G4L3C-U1CCDGWMD"))
        #expect(try BridgeInfo.receiver(roomState: state) == "T1C6G4L3C-U1CCDGWMD")
    }

    @Test
    func prefersTheBridgeEventOverTheHalfShotEvent() throws {
        let state = Self.roomState([
            Self.bridgeEvent(type: "uk.half-shot.bridge", receiver: "T1C6G4L3C-UOLD"),
            Self.bridgeEvent(type: "m.bridge", receiver: "T1C6G4L3C-UNEW"),
        ].joined(separator: ","))
        #expect(try BridgeInfo.receiver(roomState: state) == "T1C6G4L3C-UNEW")
    }

    @Test
    func aChannelWithoutReceiverGivesNoAnswer() throws {
        let absent = Self.roomState([Self.member, Self.bridgeEvent(type: "m.bridge", receiver: nil)].joined(separator: ","))
        let empty = Self.roomState(Self.bridgeEvent(type: "m.bridge", receiver: ""))
        #expect(try BridgeInfo.receiver(roomState: absent) == nil)
        #expect(try BridgeInfo.receiver(roomState: empty) == nil)
        #expect(try BridgeInfo.receiver(roomState: Self.roomState("")) == nil)
    }

    @Test
    func takesTheFirstEventThatHasAReceiver() throws {
        let state = Self.roomState([
            Self.bridgeEvent(type: "m.bridge", receiver: nil),
            Self.bridgeEvent(type: "m.bridge", receiver: "T1C6G4L3C-UFIRST"),
            Self.bridgeEvent(type: "m.bridge", receiver: "T1C6G4L3C-USECOND"),
        ].joined(separator: ","))
        #expect(try BridgeInfo.receiver(roomState: state) == "T1C6G4L3C-UFIRST")
    }

    @Test
    func fallsBackToTheHalfShotEventWhenTheBridgeEventHasNoReceiver() throws {
        let state = Self.roomState([
            Self.bridgeEvent(type: "m.bridge", receiver: nil),
            Self.bridgeEvent(type: "uk.half-shot.bridge", receiver: "T1C6G4L3C-U1CCDGWMD"),
        ].joined(separator: ","))
        #expect(try BridgeInfo.receiver(roomState: state) == "T1C6G4L3C-U1CCDGWMD")
    }

    @Test
    func skipsEventsOfAnUnexpectedShape() throws {
        let state = Self.roomState([
            "{\"type\": \"m.bridge\", \"content\": {\"channel\": \"text\"}}",
            "{\"type\": \"m.bridge\", \"content\": {\"channel\": {\"fi.mau.receiver\": 7}}}",
            "17",
            Self.bridgeEvent(type: "m.bridge", receiver: "T1C6G4L3C-U1CCDGWMD"),
        ].joined(separator: ","))
        #expect(try BridgeInfo.receiver(roomState: state) == "T1C6G4L3C-U1CCDGWMD")
    }

    @Test
    func aBodyThatIsNotAnArrayThrows() {
        #expect(throws: BridgeInfo.MalformedRoomState.self) {
            try BridgeInfo.receiver(roomState: Data("{\"errcode\": \"M_FORBIDDEN\"}".utf8))
        }
        #expect(throws: BridgeInfo.MalformedRoomState.self) {
            try BridgeInfo.receiver(roomState: Data("not json".utf8))
        }
    }
}

/// MATRIX-165: the own ghost's user ID from the receiver and a peer ghost.
struct OwnServiceGhostTests {
    private static let account = "@patrick:davlin.io"
    private static let receiver = "T1C6G4L3C-U1CCDGWMD"

    private func ghost(
        receiver: String = OwnServiceGhostTests.receiver,
        peer: String,
        account: String = OwnServiceGhostTests.account
    ) -> String? {
        OwnServiceGhost.userId(receiver: receiver, peerUserId: peer, accountUserId: account)
    }

    @Test
    func replacesTheUserPartOfThePeer() {
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def:davlin.io") == "@slack_t1c6g4l3c-u1ccdgwmd:davlin.io")
    }

    @Test
    func keepsACustomUsernamePrefix() {
        #expect(ghost(peer: "@sl_t1c6g4l3c-u0456def:davlin.io") == "@sl_t1c6g4l3c-u1ccdgwmd:davlin.io")
        #expect(ghost(peer: "@t1c6g4l3c-u0456def:davlin.io") == "@t1c6g4l3c-u1ccdgwmd:davlin.io")
    }

    @Test
    func keepsTheServerNameWithAPort() {
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def:localhost:8448") == "@slack_t1c6g4l3c-u1ccdgwmd:localhost:8448")
    }

    @Test
    func refusesAPeerOfAnotherTeam() {
        #expect(ghost(peer: "@slack_t9zzzzzzz-u0456def:davlin.io") == nil)
    }

    @Test
    func refusesALocalpartWithoutTheSegment() {
        #expect(ghost(peer: "@slackbot:davlin.io") == nil)
        #expect(ghost(peer: "@alice:davlin.io") == nil)
        #expect(ghost(peer: "@slack_t1c6g4l3c-:davlin.io") == nil)
        #expect(ghost(peer: "@slack_t1c6g4l3c:davlin.io") == nil)
    }

    @Test
    func refusesATeamSegmentThatShowsTwice() {
        #expect(ghost(peer: "@slack_t1c6g4l3c-t1c6g4l3c-u0456def:davlin.io") == nil)
    }

    @Test
    func refusesAUserPartThatDoesNotRunToTheEnd() {
        // A username template with a suffix: the user part is not known.
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def_x:davlin.io") == nil)
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def-2:davlin.io") == nil)
    }

    @Test
    func refusesAReceiverThatIsNotTeamAndUser() {
        let peer = "@slack_t1c6g4l3c-u0456def:davlin.io"
        #expect(ghost(receiver: "T1C6G4L3CU1CCDGWMD", peer: peer) == nil)
        #expect(ghost(receiver: "-U1CCDGWMD", peer: peer) == nil)
        #expect(ghost(receiver: "T1C6G4L3C-", peer: peer) == nil)
        #expect(ghost(receiver: "", peer: peer) == nil)
        #expect(ghost(receiver: "T1C6G4L3C-U1CC:evil.example", peer: peer) == nil)
        #expect(ghost(receiver: "T1C6G4L3C-U1-CC", peer: peer) == nil)
    }

    @Test
    func refusesAPeerThatIsNotAUserId() {
        #expect(ghost(peer: "slack_t1c6g4l3c-u0456def:davlin.io") == nil)
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def") == nil)
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def:") == nil)
    }

    @Test
    func refusesAChatWithOneself() {
        #expect(ghost(peer: "@slack_t1c6g4l3c-u1ccdgwmd:davlin.io") == nil)
    }

    @Test
    func refusesTheAccountsOwnId() {
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def:davlin.io", account: "@slack_t1c6g4l3c-u1ccdgwmd:davlin.io") == nil)
        #expect(ghost(peer: "@slack_t1c6g4l3c-u0456def:davlin.io", account: "@Slack_T1C6G4L3C-U1CCDGWMD:davlin.io") == nil)
    }

    @Test
    func peersLeaveOutTheAccountServicesAndBots() {
        let peers = OwnServiceGhost.peers(
            among: [
                "@slackbot:davlin.io",
                "@patrick:davlin.io",
                "@slack_t1c6g4l3c-u0456def:davlin.io",
                "@helper:davlin.io",
                "@slack_t1c6g4l3c-u0456def:davlin.io",
                "@slack_t1c6g4l3c-u0789ghi:davlin.io",
            ],
            serviceMembers: ["@helper:davlin.io"],
            accountUserId: Self.account
        )
        #expect(peers == ["@slack_t1c6g4l3c-u0456def:davlin.io", "@slack_t1c6g4l3c-u0789ghi:davlin.io"])
    }
}

/// MATRIX-165: the full avatar order of a message's profile row.
struct MessageAvatarOrderTests {
    @Test
    func serviceImageComesFirstForAnOwnMessage() {
        let url = MessageAvatarRule.avatarUrl(
            serviceAvatarUrl: "mxc://a/service",
            memberAvatarUrl: "mxc://a/member",
            accountAvatarUrl: "mxc://a/account",
            isOwn: true
        )
        #expect(url == "mxc://a/service")
    }

    @Test
    func memberThenAccountThenInitialsWithoutAServiceImage() {
        let member = MessageAvatarRule.avatarUrl(
            serviceAvatarUrl: nil, memberAvatarUrl: "mxc://a/member", accountAvatarUrl: "mxc://a/account", isOwn: true
        )
        let account = MessageAvatarRule.avatarUrl(
            serviceAvatarUrl: "", memberAvatarUrl: nil, accountAvatarUrl: "mxc://a/account", isOwn: true
        )
        let initials = MessageAvatarRule.avatarUrl(serviceAvatarUrl: nil, memberAvatarUrl: nil, accountAvatarUrl: nil, isOwn: true)
        #expect(member == "mxc://a/member")
        #expect(account == "mxc://a/account")
        #expect(initials == nil)
    }

    @Test
    func anotherUserNeverTakesTheServiceImage() {
        let withMember = MessageAvatarRule.avatarUrl(
            serviceAvatarUrl: "mxc://a/service", memberAvatarUrl: "mxc://a/member", accountAvatarUrl: "mxc://a/account", isOwn: false
        )
        let withoutMember = MessageAvatarRule.avatarUrl(
            serviceAvatarUrl: "mxc://a/service", memberAvatarUrl: nil, accountAvatarUrl: "mxc://a/account", isOwn: false
        )
        #expect(withMember == "mxc://a/member")
        #expect(withoutMember == nil)
    }

    @Test
    func theDefaultKeepsTheEarlierOrder() {
        let url = MessageAvatarRule.avatarUrl(memberAvatarUrl: "mxc://a/member", accountAvatarUrl: "mxc://a/account", isOwn: true)
        #expect(url == "mxc://a/member")
    }
}

/// MATRIX-161, MATRIX-165: when a repeated read is due.
struct ReadScheduleTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func isDue(_ schedule: inout ReadSchedule, after seconds: TimeInterval) -> Bool {
        schedule.isDue(at: Self.start + seconds, refreshInterval: 100, maxFailedReads: 2, backOff: 50)
    }

    @Test
    func aReadIsDueWhenNoneWasMadeAndWhenTheLastIsOld() {
        var schedule = ReadSchedule()
        #expect(isDue(&schedule, after: 0))
        schedule.recordSuccess(at: Self.start)
        #expect(!isDue(&schedule, after: 99))
        #expect(isDue(&schedule, after: 100))
    }

    @Test
    func failuresInARowWaitForTheBackOff() {
        var schedule = ReadSchedule()
        schedule.recordFailure(at: Self.start)
        #expect(isDue(&schedule, after: 1))
        schedule.recordFailure(at: Self.start + 1)
        #expect(!isDue(&schedule, after: 50))
        #expect(isDue(&schedule, after: 51))
        // The count started again.
        #expect(schedule.failedReads == 0)
        schedule.recordFailure(at: Self.start + 51)
        #expect(isDue(&schedule, after: 52))
    }

    @Test
    func aCachedReadTimeCountsAsAGoodRead() {
        var schedule = ReadSchedule(lastGoodRead: Self.start)
        #expect(!isDue(&schedule, after: 10))
    }
}
