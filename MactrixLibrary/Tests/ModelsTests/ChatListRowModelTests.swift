@testable import Models
import Testing

/// MATRIX-67: unread state and the VoiceOver label of a chat-list row.
struct ChatListRowModelTests {
    // MARK: Pinned tile label (MATRIX-123)

    @Test(arguments: [
        ("Seth Redacted", "Seth"),
        ("Hermes", "Hermes"),
        ("  Seth   Redacted  ", "Seth"),
        ("Brian Ruch (WhatsApp)", "Brian"),
        ("Ana\tMaria", "Ana"),
        ("@seth:example.org", "@seth:example.org"),
        ("", ""),
        ("   ", "   "),
    ])
    func firstNameIsTheFirstWord(displayName: String, expected: String) {
        #expect(ChatListRowModel.firstName(of: displayName) == expected)
    }

    @Test
    func directPinnedTitleIsTheFirstName() {
        let model = ChatListRowModel(id: "!dm", title: "Seth Redacted", isDirect: true)
        #expect(model.pinnedTitle == "Seth")
        // The tooltip and VoiceOver keep the full name.
        #expect(model.helpText == "Seth Redacted")
        #expect(model.accessibilityLabel == "Seth Redacted")
    }

    @Test
    func groupPinnedTitleKeepsTheRoomName() {
        let model = ChatListRowModel(id: "!group", title: "Family Group Chat")
        #expect(model.pinnedTitle == "Family Group Chat")
    }

    // MARK: Unread state

    @Test
    func readRoomHasNoUnreadState() {
        let unread = ChatListUnread(
            numUnreadMessages: 0,
            numUnreadNotifications: 0,
            numUnreadMentions: 0,
            isMarkedUnread: false,
            isMuted: false
        )
        #expect(unread == ChatListUnread())
    }

    @Test
    func countIsTheLargestCounter() {
        let unread = ChatListUnread(
            numUnreadMessages: 5,
            numUnreadNotifications: 2,
            numUnreadMentions: 1,
            isMarkedUnread: false,
            isMuted: false
        )
        #expect(unread.count == 5)
        #expect(unread.hasMention)
        #expect(unread.isUnread)
    }

    /// A muted room still counts its messages; the capsule only turns gray.
    @Test
    func mutedRoomKeepsItsCount() {
        let unread = ChatListUnread(
            numUnreadMessages: 7,
            numUnreadNotifications: 0,
            numUnreadMentions: 0,
            isMarkedUnread: false,
            isMuted: true
        )
        #expect(unread.count == 7)
        #expect(unread.isMuted)
        #expect(unread.isUnread)
    }

    @Test
    func markedUnreadWithoutMessagesIsUnreadWithNoCount() {
        let unread = ChatListUnread(
            numUnreadMessages: 0,
            numUnreadNotifications: 0,
            numUnreadMentions: 0,
            isMarkedUnread: true,
            isMuted: false
        )
        #expect(unread.count == 0)
        #expect(unread.isUnread)
    }

    @Test
    func accessibilityLabelNamesTitleCountAndMute() {
        let row = ChatListRowModel(
            id: "!a",
            title: "Alice",
            unread: ChatListUnread(count: 3, hasMention: true, isUnread: true, isMuted: true),
            network: .signal
        )
        #expect(row.accessibilityLabel == "Alice, Signal, mentioned, 3 unread messages, muted")
    }

    @Test
    func accessibilityLabelForAReadRoomIsTheTitle() {
        #expect(ChatListRowModel(id: "!a", title: "Alice").accessibilityLabel == "Alice")
    }

    @Test
    func filterRoundTripsThroughItsRawValue() {
        for filter in ChatListFilter.allCases {
            #expect(ChatListFilter(rawValue: filter.rawValue) == filter)
        }
    }
}
