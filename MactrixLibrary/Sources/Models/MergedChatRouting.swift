import Foundation

/// Which member room each action in a merged chat goes to (MATRIX-143,
/// M2.5-4; contract §4 M2.5 and research §5).
///
/// A merged chat is presentation only (contract §11, 2026-11-10): every SDK
/// call still goes to one member room. This type answers "which room" for
/// each kind of call, from plain values, so Phase B only has to make the
/// call on that room's `Room` or `Timeline`.
///
/// - Message actions (reply, reactions, edit, redaction, pin and unpin,
///   forward-from, copy link, the media actions) act in the room that holds
///   the event: `route(for:eventRoomId:rooms:)`.
/// - The composer sends a new message to the send target, but a reply or an
///   edit goes to the room that holds its event, for that one message only:
///   `composerTarget(for:autoTarget:rooms:)`.
/// - Typing notices go only to the composer's current target:
///   `typingNotices(previousRoom:currentRoom:isTyping:)`.
/// - Read receipts go to each member room for its own newest visible event:
///   `readReceipts(newestVisibleEvents:alreadySent:rooms:)`.
public enum MergedChatRouting {
    /// Where a message action runs.
    public enum ActionRoute: Hashable, Sendable {
        /// Make the call on this member room: the room that holds the event.
        case room(String)
        /// The action needs no room. `copyMessages` copies the selection,
        /// which can span member rooms, as local text.
        case noRoom
        /// The event's room is not a member of the merge (the merge changed
        /// under a stale row). Do nothing.
        case notAMember
    }

    /// What the composer is writing.
    public enum ComposerMode: Hashable, Sendable {
        /// A new message: it goes to the send target.
        case newMessage
        /// A reply to an event in this member room.
        case reply(eventRoomId: String)
        /// An edit of an event in this member room.
        case edit(eventRoomId: String)
    }

    /// One typing notice to send through the room's normal typing call.
    public struct TypingNotice: Hashable, Sendable {
        public var roomId: String
        public var isTyping: Bool

        public init(roomId: String, isTyping: Bool) {
            self.roomId = roomId
            self.isTyping = isTyping
        }
    }

    /// One read receipt to send through the room's normal receipt call.
    public struct ReadReceipt: Hashable, Sendable {
        public var roomId: String
        public var eventId: String

        public init(roomId: String, eventId: String) {
            self.roomId = roomId
            self.eventId = eventId
        }
    }

    /// The room a message action runs in.
    ///
    /// Every per-message action acts in the room that holds the event: a
    /// reply, a reaction, an edit, a redaction, a pin, the source of a
    /// forward, and the event's permalink all name that room. Only
    /// `copyMessages`, which acts on the selection, needs no room.
    ///
    /// - Parameters:
    ///   - action: The action from `MessageActionModel`.
    ///   - eventRoomId: The ID of the member room whose timeline holds the
    ///     event.
    ///   - rooms: The merge's member room IDs.
    /// - Returns: The route.
    public static func route(for action: MessageAction, eventRoomId: String, rooms: [String]) -> ActionRoute {
        switch action {
        case .copyMessages:
            return .noRoom
        case .reply, .replyInThread, .toggleReaction, .openReactionPicker, .edit, .forward,
             .copyText, .copyLink, .pin, .unpin, .quickLook, .playInline, .saveToDownloads, .redact:
            return rooms.contains(eventRoomId) ? .room(eventRoomId) : .notAMember
        }
    }

    /// The room the composer's next message goes to, and why.
    ///
    /// Decision (MATRIX-143): a reply goes to the room that holds the
    /// replied-to event, whatever the send-target rule says, because a
    /// Matrix reply must be in the same room as its event. An edit works the
    /// same way. This holds for that one message only: the manual pick and
    /// the automatic target do not change, so the next new message uses the
    /// send-target rule again. While the composer replies or edits, the
    /// target picker shows the event's room and is locked.
    ///
    /// - Parameters:
    ///   - mode: What the composer is writing.
    ///   - autoTarget: The target from `MergedSendTarget.resolve`, after
    ///     `MergedSendTarget.stabilized`.
    ///   - rooms: The merge's member room IDs.
    /// - Returns: The target for this message. A reply or edit whose event
    ///   room is not a member falls back to `autoTarget`.
    public static func composerTarget(
        for mode: ComposerMode,
        autoTarget: MergedSendTarget,
        rooms: [String]
    ) -> MergedSendTarget {
        switch mode {
        case .newMessage:
            return autoTarget
        case let .reply(eventRoomId):
            guard rooms.contains(eventRoomId) else { return autoTarget }
            return MergedSendTarget(roomId: eventRoomId, reason: .reply)
        case let .edit(eventRoomId):
            guard rooms.contains(eventRoomId) else { return autoTarget }
            return MergedSendTarget(roomId: eventRoomId, reason: .edit)
        }
    }

    /// The typing notices to send when the composer's typing state or its
    /// target changes.
    ///
    /// Typing goes only to the current target. When the target moves while
    /// the user types, the old room gets "stopped typing" first, so the other
    /// person does not see a typing notice that never ends.
    ///
    /// - Parameters:
    ///   - previousRoom: The room that last got a typing notice with
    ///     `isTyping == true`, or nil when no room shows the user typing.
    ///   - currentRoom: The composer's current target, or nil when there is
    ///     none.
    ///   - isTyping: Whether the user types now.
    /// - Returns: The notices in send order. Empty when nothing changes.
    public static func typingNotices(previousRoom: String?, currentRoom: String?, isTyping: Bool) -> [TypingNotice] {
        var notices: [TypingNotice] = []
        if let previousRoom, previousRoom != currentRoom || !isTyping {
            notices.append(TypingNotice(roomId: previousRoom, isTyping: false))
        }
        if isTyping, let currentRoom, currentRoom != previousRoom {
            notices.append(TypingNotice(roomId: currentRoom, isTyping: true))
        }
        return notices
    }

    /// The read receipts to send when the merged timeline shows new events.
    ///
    /// Each member room gets a receipt for its own newest visible event,
    /// through that room's normal receipt call. A room with no visible event,
    /// or whose last sent receipt is already at that event, gets none.
    ///
    /// - Parameters:
    ///   - newestVisibleEvents: The newest visible event ID per member room
    ///     ID, from the merged timeline.
    ///   - alreadySent: The event ID of the last receipt sent per room ID.
    ///   - rooms: The merge's member room IDs. Rooms that are not members are
    ///     ignored.
    /// - Returns: The receipts in member order.
    public static func readReceipts(
        newestVisibleEvents: [String: String],
        alreadySent: [String: String] = [:],
        rooms: [String]
    ) -> [ReadReceipt] {
        rooms.compactMap { roomId in
            guard let eventId = newestVisibleEvents[roomId], alreadySent[roomId] != eventId else { return nil }
            return ReadReceipt(roomId: roomId, eventId: eventId)
        }
    }
}
