import Foundation

/// The member room a merged chat's composer sends a new message to
/// (MATRIX-143, M2.5-4), and the reason for the choice.
///
/// The rule is Beeper's (contract §11, 2026-11-10; research §5
/// `resolveUnionSendTarget`), see `resolve(rooms:defaultRoom:activity:manualPick:now:)`:
/// 1. A manual pick from the target picker wins while it is still a member.
/// 2. Else find the newest message by anyone across the member rooms. A tie
///    goes to the room that comes first in member order.
/// 3. If that message is from the account's own user and is older than
///    `ownSilenceThreshold`, use the default room.
/// 4. Else use the room that holds that message.
/// 5. With no messages at all, use the default room.
///
/// So when the other person writes in room B, the answer goes to room B,
/// however long ago the account's own last message was. The default room
/// only takes over after a long silence that the user's own message ended.
///
/// A reply or an edit does not use this rule: it goes to the room that holds
/// its event (`MergedChatRouting.composerTarget(for:autoTarget:rooms:)`).
///
/// Pure value logic: the app collects the timestamps from the member rooms'
/// timelines and calls `resolve` again when they change.
public struct MergedSendTarget: Hashable, Sendable {
    /// Why the composer sends to `roomId`. The target picker shows it as a
    /// hint ("Chosen", "Last active", "Default").
    public enum Reason: Hashable, Sendable, CaseIterable {
        /// The user picked the room in the target picker.
        case chosen
        /// The message goes to the room with the newest message: someone
        /// else wrote last, or the account's own last message is recent.
        case recentActivity
        /// The newest message is the account's own and is old, or no member
        /// room has a message, so the message goes to the default room.
        case defaultRoom
        /// The composer replies to an event, so the message goes to the room
        /// that holds that event.
        case reply
        /// The composer edits an event, so the edit goes to the room that
        /// holds that event.
        case edit
    }

    /// The newest message times of one member room.
    public struct RoomActivity: Hashable, Sendable {
        /// The server time of the newest message by anyone, own messages
        /// included. Nil when the room has no loaded message.
        public var newestMessageAt: Date?
        /// The server time of the newest message by the account's own user.
        /// Nil when the loaded part of the room has none.
        public var newestOwnMessageAt: Date?

        public init(newestMessageAt: Date? = nil, newestOwnMessageAt: Date? = nil) {
            self.newestMessageAt = newestMessageAt
            self.newestOwnMessageAt = newestOwnMessageAt
        }

        /// The newest message by anyone. An own message counts even if the
        /// caller left `newestMessageAt` older or empty by mistake.
        var newestAnyMessageAt: Date? {
            switch (newestMessageAt, newestOwnMessageAt) {
            case let (any?, own?): max(any, own)
            case let (any?, nil): any
            case let (nil, own?): own
            case (nil, nil): nil
            }
        }

        /// Whether the room's newest message is the account's own. An own
        /// message with the same time as the newest counts as the newest.
        var newestIsOwn: Bool {
            guard let own = newestOwnMessageAt else { return false }
            guard let any = newestMessageAt else { return true }
            return own >= any
        }
    }

    /// When the newest message is the account's own and is older than this,
    /// a new message goes to the default room (30 minutes, as in Beeper).
    public static let ownSilenceThreshold: TimeInterval = 30 * 60

    /// The member room the message goes to.
    public var roomId: String
    /// Why the composer chose `roomId`.
    public var reason: Reason

    public init(roomId: String, reason: Reason) {
        self.roomId = roomId
        self.reason = reason
    }

    /// Whether the composer chose the room by itself, so new activity may
    /// move it (`.recentActivity` or `.defaultRoom`).
    public var isAutomatic: Bool {
        reason == .recentActivity || reason == .defaultRoom
    }

    /// Applies the send-target rule.
    ///
    /// - Parameters:
    ///   - rooms: The merge's member room IDs, in member order.
    ///   - defaultRoom: The merge's default room. Nil, or a room that is not
    ///     a member, means the first member (`MergedChat.effectiveDefaultRoom`).
    ///   - activity: The newest message times per member room ID. A missing
    ///     room counts as a room with no messages. Rooms that are not members
    ///     are ignored.
    ///   - manualPick: The room picked in the target picker, if any. A pick
    ///     that is no longer a member is ignored.
    ///   - now: The current time.
    /// - Returns: The target, or nil when `rooms` is empty.
    ///
    /// ```swift
    /// let target = MergedSendTarget.resolve(
    ///     rooms: ["!a:x", "!b:x"], defaultRoom: "!a:x",
    ///     activity: ["!b:x": .init(newestMessageAt: fiveMinutesAgo, newestOwnMessageAt: tenMinutesAgo)],
    ///     manualPick: nil, now: .now
    /// )
    /// // target == MergedSendTarget(roomId: "!b:x", reason: .recentActivity)
    /// ```
    public static func resolve(
        rooms: [String],
        defaultRoom: String?,
        activity: [String: RoomActivity],
        manualPick: String?,
        now: Date
    ) -> MergedSendTarget? {
        guard let firstRoom = rooms.first else { return nil }

        if let manualPick, rooms.contains(manualPick) {
            return MergedSendTarget(roomId: manualPick, reason: .chosen)
        }

        let fallback: String = if let defaultRoom, rooms.contains(defaultRoom) {
            defaultRoom
        } else {
            firstRoom
        }
        let defaultTarget = MergedSendTarget(roomId: fallback, reason: .defaultRoom)

        var newest: (roomId: String, at: Date)?
        var newestIsOwn = false
        for roomId in rooms {
            guard let roomActivity = activity[roomId], let at = roomActivity.newestAnyMessageAt else { continue }
            // Strictly newer, so a tie keeps the earlier member.
            if let current = newest, at <= current.at { continue }
            newest = (roomId, at)
            newestIsOwn = roomActivity.newestIsOwn
        }
        guard let newest else { return defaultTarget }
        if newestIsOwn, now.timeIntervalSince(newest.at) > ownSilenceThreshold {
            return defaultTarget
        }
        return MergedSendTarget(roomId: newest.roomId, reason: .recentActivity)
    }

    /// Applies the send-target rule to a merged chat.
    ///
    /// - Parameters:
    ///   - merge: The merged chat. Its members and its effective default
    ///     room feed the rule.
    ///   - activity: The newest message times per member room ID.
    ///   - manualPick: The room picked in the target picker, if any.
    ///   - now: The current time.
    /// - Returns: The target, or nil when the merge has no members.
    public static func resolve(
        for merge: MergedChat,
        activity: [String: RoomActivity],
        manualPick: String?,
        now: Date
    ) -> MergedSendTarget? {
        resolve(
            rooms: merge.rooms,
            defaultRoom: merge.effectiveDefaultRoom,
            activity: activity,
            manualPick: manualPick,
            now: now
        )
    }

    /// Keeps the shown target stable while the user writes.
    ///
    /// New activity can move an automatic target. If that happens while the
    /// composer holds text, the message could go to a room the user did not
    /// see when they started to write. So while the composer has content,
    /// the previous target stays, if it is still a member. A manual pick
    /// always takes effect at once: `resolved` with reason `.chosen` wins.
    ///
    /// - Parameters:
    ///   - resolved: The target from `resolve` for the current state.
    ///   - previous: The target the composer showed before, if any.
    ///   - composerHasContent: Whether the composer holds text or attachments.
    ///   - rooms: The merge's member room IDs.
    /// - Returns: The target the composer shows and sends to.
    public static func stabilized(
        _ resolved: MergedSendTarget,
        previous: MergedSendTarget?,
        composerHasContent: Bool,
        rooms: [String]
    ) -> MergedSendTarget {
        guard composerHasContent,
              resolved.isAutomatic,
              let previous,
              previous.isAutomatic,
              rooms.contains(previous.roomId)
        else {
            return resolved
        }
        return previous
    }
}
