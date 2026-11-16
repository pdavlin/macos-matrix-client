import Models
import Testing

/// MATRIX-163: which avatar a message's profile row draws.
struct MessageAvatarRuleTests {
    @Test
    func memberAvatarWinsForOwnMessage() {
        let url = MessageAvatarRule.avatarUrl(memberAvatarUrl: "mxc://a/member", accountAvatarUrl: "mxc://a/account", isOwn: true)
        #expect(url == "mxc://a/member")
    }

    @Test
    func ownMessageFallsBackToAccountAvatar() {
        let url = MessageAvatarRule.avatarUrl(memberAvatarUrl: nil, accountAvatarUrl: "mxc://a/account", isOwn: true)
        #expect(url == "mxc://a/account")
    }

    @Test
    func emptyMemberAvatarCountsAsAbsent() {
        let url = MessageAvatarRule.avatarUrl(memberAvatarUrl: "", accountAvatarUrl: "mxc://a/account", isOwn: true)
        #expect(url == "mxc://a/account")
    }

    @Test
    func ownMessageWithoutAnyAvatarDrawsInitials() {
        let absent = MessageAvatarRule.avatarUrl(memberAvatarUrl: nil, accountAvatarUrl: nil, isOwn: true)
        let empty = MessageAvatarRule.avatarUrl(memberAvatarUrl: "", accountAvatarUrl: "", isOwn: true)
        #expect(absent == nil)
        #expect(empty == nil)
    }

    @Test
    func otherUserNeverTakesAccountAvatar() {
        let absent = MessageAvatarRule.avatarUrl(memberAvatarUrl: nil, accountAvatarUrl: "mxc://a/account", isOwn: false)
        let empty = MessageAvatarRule.avatarUrl(memberAvatarUrl: "", accountAvatarUrl: "mxc://a/account", isOwn: false)
        #expect(absent == nil)
        #expect(empty == nil)
    }

    @Test
    func otherUserKeepsMemberAvatar() {
        let url = MessageAvatarRule.avatarUrl(memberAvatarUrl: "mxc://a/other", accountAvatarUrl: "mxc://a/account", isOwn: false)
        #expect(url == "mxc://a/other")
    }
}
