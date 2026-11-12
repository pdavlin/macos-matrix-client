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

@Suite("ChatListNetwork bridge bot")
struct ChatListNetworkBridgeBotTests {
    @Test
    func theBridgeBotNamesTheNetwork() {
        #expect(ChatListNetwork.detect(heroUserIds: ["@slackbot:davlin.io"]) == .slack)
        #expect(ChatListNetwork.detect(heroUserIds: ["@seth:example.org", "@googlechatbot:davlin.io"]) == .googleChat)
        #expect(ChatListNetwork.detect(heroUserIds: ["@robot:example.org", "@slackbotfan:example.org"]) == nil)
    }
}

@Suite("ChatAccount and ChatBadge")
struct ChatAccountTests {
    @Test
    func theAccountIsTheFirstSpaceThatIsNotTheNetwork() {
        let spaces = [ChatAccount(name: "Slack"), ChatAccount(name: " DevObsessed ", avatarUrl: "mxc://a/b")]
        #expect(ChatAccount.choose(from: spaces, network: .slack) == ChatAccount(name: "DevObsessed", avatarUrl: "mxc://a/b"))
        #expect(ChatAccount.choose(from: spaces, network: nil)?.name == "Slack")
        #expect(ChatAccount.choose(from: [], network: .slack) == nil)
    }

    @Test
    func aPlainRowHasOneBadgeAndAMergedRowOnePerAccount() {
        var plain = ChatListRowModel(id: "!a", title: "Seth", network: .slack)
        plain.account = ChatAccount(name: "DevObsessed", avatarUrl: "mxc://a/b")
        #expect(plain.badges == [ChatBadge(network: .slack, account: plain.account)])
        #expect(ChatListRowModel(id: "!n", title: "Seth").badges.isEmpty)

        var other = ChatListRowModel(id: "!b", title: "Seth", network: .slack)
        other.account = ChatAccount(name: "pizza box audit committee", avatarUrl: "mxc://a/c")
        let merge = MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b"])
        let merged = ChatListMerging.entry(for: merge, members: [ChatListEntry(row: plain), ChatListEntry(row: other)])
        #expect(merged?.row.badges.map(\.account?.name) == ["DevObsessed", "pizza box audit committee"])
    }
}
