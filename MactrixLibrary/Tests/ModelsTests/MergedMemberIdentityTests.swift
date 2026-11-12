import Models
import Testing

@Suite("MergedMemberIdentity")
struct MergedMemberIdentityTests {
    @Test
    func networkAndAccount() {
        let identity = MergedMemberIdentity(
            network: .slack, parentNames: ["DevObsessed"], peerUserId: "@slack_t1-u1:davlin.io", roomName: "Seth"
        )
        #expect(identity.account == "DevObsessed")
        #expect(identity.distinguishingName == "DevObsessed")
        #expect(identity.detail == "Slack • DevObsessed")
    }

    @Test
    func aSpaceNamedAsTheNetworkIsNotAnAccount() {
        let identity = MergedMemberIdentity(
            network: .slack, parentNames: [" slack ", "", "pizza box audit committee"], peerUserId: nil, roomName: "Seth"
        )
        #expect(identity.detail == "Slack • pizza box audit committee")
    }

    @Test
    func networkAloneShowsNoPuppetId() {
        let identity = MergedMemberIdentity(
            network: .slack, parentNames: ["Slack"], peerUserId: "@slack_t1-u1:davlin.io", roomName: "Seth"
        )
        #expect(identity.distinguishingName == nil)
        #expect(identity.detail == "Slack")
    }

    @Test
    func accountWithoutNetwork() {
        let identity = MergedMemberIdentity(
            network: nil, parentNames: ["Google Chat"], peerUserId: "@u:beeper.com", roomName: "Seth"
        )
        #expect(identity.detail == "Google Chat")
    }

    @Test
    func noNetworkAndNoAccountFallsBackToTheUserIdThenTheRoomName() {
        let withPeer = MergedMemberIdentity(network: nil, parentNames: [], peerUserId: "@seth:example.org", roomName: "Seth")
        #expect(withPeer.detail == "@seth:example.org")
        let withName = MergedMemberIdentity(network: nil, parentNames: [], peerUserId: nil, roomName: "Seth")
        #expect(withName.detail == "Seth")
        let empty = MergedMemberIdentity(network: nil, parentNames: [], peerUserId: nil, roomName: " ")
        #expect(empty.detail == nil)
    }

    @Test
    func memberLabelsUseTheDetails() {
        let labels = MergedChatDraft.memberLabels(
            for: [
                ChatListRowModel(id: "!a", title: "Seth", network: .slack),
                ChatListRowModel(id: "!b", title: "Seth", network: .slack),
                ChatListRowModel(id: "!c", title: "Seth"),
            ],
            details: ["!a": "Slack • DevObsessed", "!c": "@seth:example.org"]
        )
        #expect(labels == ["Seth · Slack • DevObsessed", "Seth · Slack", "Seth · @seth:example.org"])
    }
}
