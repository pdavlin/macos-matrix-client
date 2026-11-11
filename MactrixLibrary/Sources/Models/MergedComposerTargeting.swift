import Foundation

/// The send target of one merged chat's composer, kept from one update to
/// the next (MATRIX-143 Phase B).
///
/// `MergedSendTarget.resolve` tells where a new message goes now. The
/// composer must also keep that target still while the user writes
/// (`MergedSendTarget.stabilized`), and that needs the target it showed
/// before. This value keeps that memory, so the app gives it only the current
/// facts: the member activity, the manual pick, whether the composer has
/// content, and the time.
///
/// A reply or an edit does not change the memory. It goes to the room of its
/// event for that one message (`target(for:rooms:)`), and the next new
/// message uses the send-target rule again.
///
/// Usage:
/// ```swift
/// var targeting = MergedComposerTargeting()
/// targeting.update(merge: merge, activity: activity, manualPick: nil, composerHasContent: false, now: .now)
/// let mode = MergedComposerTargeting.mode(editRoomId: nil, replyRoomId: "!b:x")
/// let target = targeting.target(for: mode, rooms: merge.rooms)
/// // target?.roomId == "!b:x", target?.reason == .reply
/// ```
public struct MergedComposerTargeting: Equatable, Sendable {
    /// The target for a new message, after stabilization. Nil before the
    /// first update, and for a merge with no member room.
    public private(set) var newMessageTarget: MergedSendTarget?
    /// Whether `newMessageTarget` was chosen with every member's activity
    /// known.
    private var previousActivityWasKnown = false

    public init() {}

    /// Applies the send-target rule to the current facts, and keeps the
    /// previous target while the composer has content.
    ///
    /// Call it when any input changes: the member activity, the manual pick,
    /// the merge (its members or its default room), whether the composer has
    /// content, and from time to time, because an old own message moves the
    /// target to the default room after `MergedSendTarget.ownSilenceThreshold`.
    ///
    /// - Parameters:
    ///   - merge: The merged chat, with its current members and default room.
    ///   - activity: The newest message times per member room ID
    ///     (`MergedLiveTimeline.activity`).
    ///   - manualPick: The room the user picked in the target picker, or nil
    ///     for the automatic choice.
    ///   - composerHasContent: Whether the composer holds text or
    ///     attachments.
    ///   - activityIsKnown: False while a member room has not loaded its
    ///     newest messages (`MergedLiveTimeline.boundary == .pending`). The
    ///     target is not kept then, even with content: a composer that
    ///     opens with a saved draft must not keep the default room only
    ///     because the room with the newest message loaded second.
    ///   - now: The current time.
    /// - Returns: Whether `newMessageTarget` changed.
    @discardableResult
    public mutating func update(
        merge: MergedChat,
        activity: [String: MergedSendTarget.RoomActivity],
        manualPick: String?,
        composerHasContent: Bool,
        activityIsKnown: Bool = true,
        now: Date
    ) -> Bool {
        let previous = newMessageTarget
        // A target chosen while the activity was unknown is not one to keep.
        let keepable = previousActivityWasKnown ? previous : nil
        previousActivityWasKnown = activityIsKnown
        if let resolved = MergedSendTarget.resolve(for: merge, activity: activity, manualPick: manualPick, now: now) {
            newMessageTarget = MergedSendTarget.stabilized(
                resolved,
                previous: keepable,
                composerHasContent: composerHasContent && activityIsKnown,
                rooms: merge.rooms
            )
        } else {
            newMessageTarget = nil
        }
        return newMessageTarget != previous
    }

    /// The target of the composer's next message in `mode`.
    ///
    /// - Parameters:
    ///   - mode: What the composer writes (`mode(editRoomId:replyRoomId:)`).
    ///   - rooms: The merge's member room IDs.
    /// - Returns: The event's room for a reply or an edit, else
    ///   `newMessageTarget`. Nil before the first update.
    public func target(for mode: MergedChatRouting.ComposerMode, rooms: [String]) -> MergedSendTarget? {
        guard let newMessageTarget else { return nil }
        return MergedChatRouting.composerTarget(for: mode, autoTarget: newMessageTarget, rooms: rooms)
    }

    /// The composer mode from the room of the composer's edit and the room
    /// of its reply.
    ///
    /// The composer never edits and replies at the same time (an edit clears
    /// the reply, and a reply ends the edit), but if both are set the edit
    /// wins, because Return saves the edit.
    ///
    /// - Parameters:
    ///   - editRoomId: The member room of the message being edited, or nil.
    ///   - replyRoomId: The member room of the message being replied to, or
    ///     nil.
    public static func mode(editRoomId: String?, replyRoomId: String?) -> MergedChatRouting.ComposerMode {
        if let editRoomId {
            return .edit(eventRoomId: editRoomId)
        }
        if let replyRoomId {
            return .reply(eventRoomId: replyRoomId)
        }
        return .newMessage
    }
}

public extension MergedChatRouting {
    /// The typing notices for one change of the merged composer's text or
    /// target (MATRIX-143 Phase B).
    ///
    /// The same as `typingNotices(previousRoom:currentRoom:isTyping:)`, with
    /// one addition: while the user keeps typing in the same room, the room
    /// gets `isTyping == true` again. The single-room composer sends that
    /// notice on every text change, and the SDK limits how often it goes to
    /// the server; without the repeat, the other person would see the typing
    /// notice end while the user still types.
    ///
    /// - Parameters:
    ///   - previousRoom: The room that last got `isTyping == true`, or nil.
    ///   - currentRoom: The composer's current target, or nil.
    ///   - isTyping: Whether the composer has text now.
    /// - Returns: The notices in send order.
    static func composerTypingNotices(previousRoom: String?, currentRoom: String?, isTyping: Bool) -> [TypingNotice] {
        let notices = typingNotices(previousRoom: previousRoom, currentRoom: currentRoom, isTyping: isTyping)
        guard notices.isEmpty, isTyping, let currentRoom else { return notices }
        return [TypingNotice(roomId: currentRoom, isTyping: true)]
    }

    /// The room that shows the user typing after `notices` were sent.
    ///
    /// - Parameters:
    ///   - notices: The notices from `composerTypingNotices`.
    ///   - previousRoom: The room that showed the user typing before.
    /// - Returns: The room of the last `isTyping == true` notice; nil when a
    ///   stop went to `previousRoom` and no start followed; else
    ///   `previousRoom`.
    static func typingRoom(after notices: [TypingNotice], previousRoom: String?) -> String? {
        var room = previousRoom
        for notice in notices {
            if notice.isTyping {
                room = notice.roomId
            } else if notice.roomId == room {
                room = nil
            }
        }
        return room
    }
}
