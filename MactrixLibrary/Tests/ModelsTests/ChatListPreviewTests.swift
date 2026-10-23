import Foundation
@testable import Models
import Testing

/// MATRIX-67: the preview line under a chat-list row's title.
struct ChatListPreviewTests {
    private static let alice = ChatListSender(userId: "@alice:example.org", displayName: "Alice", isOwn: false)
    private static let me = ChatListSender(userId: "@me:example.org", displayName: "Patrick", isOwn: true)
    private static let anonymous = ChatListSender(userId: "@whatsapp_123:example.org", displayName: nil, isOwn: false)

    private func preview(
        _ content: ChatListPreviewContent,
        from sender: ChatListSender = alice,
        isDirect: Bool = false,
        failed: Bool = false
    ) -> ChatListPreview {
        ChatListLatestEvent(timestamp: .now, sender: sender, content: content, hasSendFailure: failed)
            .preview(isDirect: isDirect)
    }

    // MARK: Prefixes

    @Test
    func ownMessageIsPrefixedWithYou() {
        #expect(preview(.text("On my way"), from: Self.me).text == "You: On my way")
        #expect(preview(.text("On my way"), from: Self.me, isDirect: true).text == "You: On my way")
    }

    @Test
    func groupMessageIsPrefixedWithSenderName() {
        #expect(preview(.text("Hello")).text == "Alice: Hello")
    }

    @Test
    func groupSenderWithoutDisplayNameFallsBackToLocalpart() {
        #expect(preview(.text("Hello"), from: Self.anonymous).text == "whatsapp_123: Hello")
    }

    @Test
    func directMessageFromTheOtherPersonHasNoPrefix() {
        #expect(preview(.text("Hello"), isDirect: true).text == "Hello")
    }

    // MARK: Content kinds

    @Test(arguments: [
        (ChatListPreviewContent.image, "Photo"),
        (.video, "Video"),
        (.audio, "Audio"),
        (.file(name: "report.pdf"), "report.pdf"),
        (.gallery, "Photos"),
        (.sticker, "Sticker"),
        (.poll(question: "Lunch?"), "Poll: Lunch?"),
        (.location, "Location"),
        (.redacted, "Message deleted"),
        (.unableToDecrypt, "Encrypted message"),
    ])
    func mediaAndPlaceholderKindsBecomeWords(content: ChatListPreviewContent, expected: String) {
        #expect(preview(content, isDirect: true).text == expected)
        #expect(preview(content).text == "Alice: \(expected)")
    }

    @Test
    func emoteNamesTheSenderWithoutPrefix() {
        #expect(preview(.emote("waves")).text == "* Alice waves")
        #expect(preview(.emote("waves"), from: Self.me).text == "* Patrick waves")
    }

    @Test
    func inviteReadsInvitedYou() {
        #expect(preview(.invite).text == "Invited you")
        #expect(preview(.invite, isDirect: true).text == "Invited you")
    }

    @Test
    func membershipChangesNameTheMember() {
        #expect(preview(.membership(.joined)).text == "Alice joined")
        #expect(preview(.membership(.left)).text == "Alice left")
        #expect(preview(.membership(.invited)).text == "Alice was invited")
        #expect(preview(.membership(.other)).text == nil)
    }

    @Test
    func otherEventsShowNoPreview() {
        #expect(preview(.other).text == nil)
    }

    // MARK: Text handling

    @Test
    func newlinesCollapseToSpaces() {
        #expect(preview(.text("first line\n\n  second line\r\nthird"), isDirect: true).text == "first line second line third")
    }

    @Test
    func blankTextShowsNoPreview() {
        #expect(preview(.text(" \n ")).text == nil)
    }

    // MARK: Send failure

    @Test
    func sendFailureIsCarriedThrough() {
        let failed = preview(.text("Hi"), from: Self.me, failed: true)
        #expect(failed.hasSendFailure)
        #expect(failed.text == "You: Hi")
        #expect(!preview(.text("Hi")).hasSendFailure)
    }

    // MARK: Localpart

    @Test
    func localpartStripsSigilAndServer() {
        #expect(ChatListSender.localpart(of: "@bob:matrix.org") == "bob")
        #expect(ChatListSender.localpart(of: "bob") == "bob")
    }
}
