import Foundation
@testable import Models
import Testing

/// MATRIX-180: a chat with the Matrix low priority tag adds nothing to the
/// badge of a rail space item.
struct ChatListRailLowPriorityTests {
    /// Two top-level spaces. `!both` is in both. `!deep` is in `!sub`, a
    /// sub-space of `!dev`.
    private static let spaces = RoomSpaceMap(parents: [
        "!s1": ["!dev"],
        "!w1": ["!dev"],
        "!f1": ["!pizza"],
        "!both": ["!dev", "!pizza"],
        "!deep": ["!sub"],
        "!sub": ["!dev"],
    ])

    private static let allIds = ["!s1", "!w1", "!f1", "!both", "!deep"]

    private static let joined = [
        ChatListRailSpace(id: "!dev", name: "DevObsessed"),
        ChatListRailSpace(id: "!pizza", name: "pizza box audit committee"),
    ]

    /// The space items from the tracker's states, as the sidebar calls it.
    private func spaceBadges(_ chats: [UnreadChatState], labelMuted: Set<String> = []) -> [ChatLabelBadge] {
        ChatListRailSpace.items(
            joined: Self.joined,
            spaces: Self.spaces,
            chatIds: Self.allIds,
            chats: Dictionary(uniqueKeysWithValues: chats.map { ($0.roomId, $0) }),
            labelMutedRoomIds: labelMuted
        ).map(\.badge)
    }

    @Test
    func unreadLowPriorityChatGivesTheSpaceNoCountAndNoDot() {
        let badges = spaceBadges([
            UnreadChatState(roomId: "!s1", numUnreadNotifications: 3, numUnreadMessages: 3, isLowPriority: true),
            UnreadChatState(roomId: "!f1", isMarkedUnread: true, isLowPriority: true),
        ])
        #expect(badges == [.none, .none])
    }

    @Test
    func mutedLowPriorityChatGivesTheSpaceNoDot() {
        let badges = spaceBadges(
            [
                UnreadChatState(roomId: "!s1", numUnreadMessages: 3, isMuted: true, isLowPriority: true),
                UnreadChatState(roomId: "!f1", numUnreadMessages: 2, isLowPriority: true),
            ],
            labelMuted: ["!f1"]
        )
        #expect(badges == [.none, .none])
    }

    @Test
    func spaceCountsOnlyTheChatsThatAreNotLowPriority() {
        let badges = spaceBadges([
            UnreadChatState(roomId: "!s1", numUnreadMessages: 3),
            UnreadChatState(roomId: "!w1", numUnreadMessages: 4, isLowPriority: true),
            UnreadChatState(roomId: "!deep", numUnreadNotifications: 1),
            // In both spaces, low priority: it adds to neither.
            UnreadChatState(roomId: "!both", numUnreadMessages: 7, isLowPriority: true),
            UnreadChatState(roomId: "!f1", numUnreadMessages: 2, isMuted: true),
        ])
        #expect(badges == [.count(2), .dot])
    }

    @Test
    func spaceBadgeFollowsTheTagInBothDirections() {
        var chat = UnreadChatState(roomId: "!s1", numUnreadMessages: 3)
        #expect(spaceBadges([chat]).first == .count(1))

        // The tag alone makes a new state, so the tracker publishes it.
        let untagged = chat
        chat.isLowPriority = true
        #expect(chat != untagged)
        #expect(spaceBadges([chat]).first == ChatLabelBadge.none)

        chat.isLowPriority = false
        #expect(chat == untagged)
        #expect(spaceBadges([chat]).first == .count(1))
    }
}
