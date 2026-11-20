import Foundation

/// When a message is a thread root that the main column shows as one
/// (MATRIX-216): its thread summary has at least one reply.
///
/// The SDK gives a message a summary with no reply as soon as a thread
/// timeline opens on it ("Reply in Thread" before the first reply): its
/// event cache counts the thread replies it holds, and there are none. Such
/// a message shows no chip, and a reply to it from the main composer is not
/// a thread reply (`ReplyRoute`).
public enum ThreadRootRule {
    /// - Parameter replyCount: the reply count of the message's thread
    ///   summary, or nil when the message has no summary.
    public static func isThreadRoot(replyCount: UInt64?) -> Bool {
        (replyCount ?? 0) > 0
    }
}

/// The reply count text of a thread (MATRIX-183): "1 reply", "4 replies".
/// The panel header, the main-column chip, and the panel's divider row use
/// it, so the three always say the same.
public enum ThreadReplyCount {
    /// The count with its noun, singular for one.
    public static func label(_ count: Int) -> String {
        count == 1 ? "1 reply" : "\(count) replies"
    }
}

/// The text of the thread panel header (MATRIX-183).
public enum ThreadPanelHeaderText {
    /// The panel title.
    public static let title = "Thread"

    /// The line under the title: "<room> · N replies". Without a count (the
    /// thread still loads) it is the room name only; without a room name it
    /// is the count only. Nil when neither is known.
    public static func subtitle(roomName: String?, replyCount: Int?) -> String? {
        let room = roomName.flatMap { $0.isEmpty ? nil : $0 }
        let count = replyCount.map(ThreadReplyCount.label)
        switch (room, count) {
        case let (room?, count?):
            return "\(room) · \(count)"
        case let (room?, nil):
            return room
        case let (nil, count?):
            return count
        case (nil, nil):
            return nil
        }
    }
}

/// The placeholder of the composer (MATRIX-183).
public enum ComposerPlaceholder {
    /// The placeholder of a composer whose timeline is a thread.
    public static let thread = "Reply in thread…"

    /// - Parameters:
    ///   - isThreadTimeline: true when the composer's timeline is a thread
    ///     (`LiveTimeline.focusedThreadId != nil`): the thread panel's
    ///     composer.
    ///   - mergedPlaceholder: the merged chat's placeholder, or nil for a
    ///     room's composer.
    ///   - roomName: the room's display name.
    /// - Returns: "Reply in thread…" in a thread, else the merged chat's
    ///   placeholder, else "Message <room>".
    public static func text(isThreadTimeline: Bool, mergedPlaceholder: String?, roomName: String?) -> String {
        if isThreadTimeline {
            return thread
        }
        return mergedPlaceholder ?? "Message \(roomName ?? "room")"
    }
}

/// The thread that the window's inspector shows (MATRIX-183).
public struct OpenThreadPanel: Equatable, Sendable {
    /// The room of the thread.
    public let roomId: String
    /// The event ID of the thread root.
    public let rootEventId: String

    public init(roomId: String, rootEventId: String) {
        self.roomId = roomId
        self.rootEventId = rootEventId
    }

    /// The thread root if the panel shows a thread of `roomId`, else nil
    /// (MATRIX-216).
    public func rootEventId(inRoom roomId: String) -> String? {
        self.roomId == roomId ? rootEventId : nil
    }
}

/// When a main-column row draws the mark of the open thread (MATRIX-183):
/// the existing focus background, on the root of the thread that the panel
/// shows. The mark goes away when the panel closes or shows another thread.
public enum OpenThreadMark {
    /// - Parameters:
    ///   - rowEventId: the event ID of the row.
    ///   - rowRoomId: the room of the row's timeline, or nil.
    ///   - rowTimelineIsThread: true when the row is in a thread timeline
    ///     (the panel itself). The panel root draws its band instead.
    ///   - panel: the thread the visible inspector shows, or nil when the
    ///     inspector is closed or shows something else.
    public static func isMarked(
        rowEventId: String,
        rowRoomId: String?,
        rowTimelineIsThread: Bool,
        panel: OpenThreadPanel?
    ) -> Bool {
        guard !rowTimelineIsThread, let panel, let rowRoomId else { return false }
        return panel.roomId == rowRoomId && panel.rootEventId == rowEventId
    }
}
