import Foundation

/// The Dock badge with merged chats (MATRIX-144).
///
/// The badge counts chats, not messages (MATRIX-119). A merged chat is one
/// chat, so it adds at most one, however many of its member rooms are unread.
public extension DockBadge {
    /// The number of chats with unread activity, where every merged chat
    /// counts as one chat.
    ///
    /// Each room is judged by `counts(_:isMutedByLabel:)` with its own mute.
    /// A merged chat adds one when at least one member room counts. A muted
    /// member therefore adds nothing, and its unmuted siblings still can: the
    /// same "follow the member's own mute" rule as the notifications (see
    /// `MergedNotificationRemap`). A merged chat whose members are all muted
    /// never counts.
    ///
    /// With an empty document the result equals
    /// `unreadChatCount(_:labelMutedRoomIds:)`.
    ///
    /// - Parameters:
    ///   - chats: the unread inputs of every non-space room.
    ///   - labelMutedRoomIds: `ChatLabelDocument.labelMutedRoomIds`.
    ///   - mergedChats: the account's merged chats.
    /// - Returns: the count, zero or more.
    static func unreadChatCount(
        _ chats: some Sequence<UnreadChatState>,
        labelMutedRoomIds: Set<String>,
        mergedChats: MergedChatDocument
    ) -> Int {
        var mergedChatIdByRoom: [String: String] = [:]
        for merge in mergedChats.merges {
            for room in merge.rooms where mergedChatIdByRoom[room] == nil {
                mergedChatIdByRoom[room] = merge.id
            }
        }

        var unmergedCount = 0
        var unreadMergedChatIds: Set<String> = []
        for chat in chats where counts(chat, isMutedByLabel: labelMutedRoomIds.contains(chat.roomId)) {
            if let mergedChatId = mergedChatIdByRoom[chat.roomId] {
                unreadMergedChatIds.insert(mergedChatId)
            } else {
                unmergedCount += 1
            }
        }
        return unmergedCount + unreadMergedChatIds.count
    }
}
