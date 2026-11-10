import Foundation

/// How a local notification for a new message shows when its room may belong
/// to a merged chat (MATRIX-144, contract §4 M2.5: "member messages notify
/// with the merged chat's name and avatar and respect its mute").
///
/// Pure presentation logic, kept out of `MatrixNotifications` so the rule is
/// unit tested without `UNUserNotificationCenter` or an SDK notification.
///
/// Format. The notification today has a title `"<sender> (<room name>)"` and
/// the message text in the subtitle; DMs use the same format, with the other
/// person's name as the room name. A member of a merged chat keeps that format
/// and puts the merged chat's name in place of the room name. The subtitle
/// does not change. The source room's network or account is not shown: the
/// format has no field for it, and the parentheses already hold the chat name.
///
/// Grouping. A member notification carries the merged chat's ID as its thread
/// identifier, so macOS stacks the notifications of every member together.
/// A room that is not merged keeps no thread identifier, the same as before
/// MATRIX-144.
///
/// Mute (orchestrator decision 2026-11-10): a merged chat is muted when every
/// member room is muted, and muting it mutes every member room. A member that
/// is muted while a sibling is not is an inconsistent state; the notification
/// then follows the member's own mute and does not post. This needs no code
/// here: per-room mute is a push rule, so the SDK does not report the event,
/// and the MATRIX-77 label mute is still read for the member room
/// (`NotificationDecision.decide(isMutedByLabel:settings:)`). A merged chat
/// whose members are all muted therefore never notifies.
public struct MergedNotificationRemap: Equatable, Sendable {
    /// The notification title.
    public var title: String
    /// `UNNotificationContent.threadIdentifier`: the merged chat's ID, or nil
    /// (leave the content's default) for a room that is not merged.
    public var threadIdentifier: String?
    /// The rooms whose avatar the notification may show, best first. Use the
    /// first one that has an avatar. For a merged chat: its `avatarRoom` when
    /// that is still a member, then every member in order (the "first member
    /// room with an avatar" rule of `MergedChat.avatarRoom`). For a room that
    /// is not merged: that room only.
    public var avatarRoomCandidates: [String]
    /// The merged chat that holds the room, or nil.
    public var mergedChatId: String?

    public init(title: String, threadIdentifier: String?, avatarRoomCandidates: [String], mergedChatId: String?) {
        self.title = title
        self.threadIdentifier = threadIdentifier
        self.avatarRoomCandidates = avatarRoomCandidates
        self.mergedChatId = mergedChatId
    }

    /// The title of a message notification, `"<sender> (<chat name>)"`. The
    /// same format `MatrixNotifications` used before MATRIX-144.
    ///
    /// - Parameters:
    ///   - senderDisplayName: the sender's display name, or the sender's user
    ///     ID when it has none.
    ///   - chatName: the room's display name, or the merged chat's name.
    public static func title(senderDisplayName: String, chatName: String) -> String {
        "\(senderDisplayName) (\(chatName))"
    }

    /// Decides how a message notification from `roomId` shows.
    ///
    /// With an empty document (no merges) the result is the notification of
    /// before MATRIX-144: the room's own name, no thread identifier.
    ///
    /// Example: Seth writes in `!slack1`, which is a member of the merged chat
    /// "Seth" with ID `m1`. The title is `"Seth (Seth)"`, the thread identifier
    /// is `m1`, and a message from `!slack2` (the other member) stacks with it.
    ///
    /// - Parameters:
    ///   - roomId: the room the notification comes from.
    ///   - roomDisplayName: that room's display name.
    ///   - senderDisplayName: the sender's display name, or the sender's user
    ///     ID when it has none.
    ///   - document: the account's merged chats.
    /// - Returns: the title, thread identifier, and avatar rooms to use.
    public static func remap(
        roomId: String,
        roomDisplayName: String,
        senderDisplayName: String,
        document: MergedChatDocument
    ) -> MergedNotificationRemap {
        guard let merge = document.merge(containing: roomId) else {
            return MergedNotificationRemap(
                title: title(senderDisplayName: senderDisplayName, chatName: roomDisplayName),
                threadIdentifier: nil,
                avatarRoomCandidates: [roomId],
                mergedChatId: nil
            )
        }
        let trimmedName = merge.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let chatName = trimmedName.isEmpty ? roomDisplayName : trimmedName
        return MergedNotificationRemap(
            title: title(senderDisplayName: senderDisplayName, chatName: chatName),
            threadIdentifier: merge.id,
            avatarRoomCandidates: avatarRoomCandidates(of: merge),
            mergedChatId: merge.id
        )
    }

    /// The explicit avatar room when it is still a member, then every member
    /// in order, without repeats.
    private static func avatarRoomCandidates(of merge: MergedChat) -> [String] {
        var candidates: [String] = []
        if let avatarRoom = merge.avatarRoom, merge.rooms.contains(avatarRoom) {
            candidates.append(avatarRoom)
        }
        for room in merge.rooms where !candidates.contains(room) {
            candidates.append(room)
        }
        return candidates
    }
}
