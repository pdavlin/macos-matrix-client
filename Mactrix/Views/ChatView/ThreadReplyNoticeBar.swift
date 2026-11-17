import Core
import Models
import SwiftUI
import UI

/// The notice above the main composer for a reply to a thread that was not
/// sent (MATRIX-173). It shows nothing while every such reply is sent or on
/// its way (`Models.ThreadReplyNotice`).
///
/// The timeline's `threadReplies` feeds it from the send state of the thread
/// timelines the composer sent to.
struct ThreadReplyNoticeBar: View {
    @Environment(WindowState.self) private var windowState

    let timeline: LiveTimeline
    /// False where no thread panel is available (a merged chat).
    var canOpenThread = true

    /// The root of the thread that the thread panel shows for this room. The
    /// panel shows the failure on the echo itself, so that thread needs no
    /// notice.
    private var shownThreadRoot: String? {
        guard windowState.inspectorVisible,
              case let .focusThread(threadTimeline: shown) = windowState.inspectorContent,
              shown.room.id == timeline.room.id
        else { return nil }
        return shown.focusedThreadId
    }

    private var notice: ThreadReplyNotice? {
        ThreadReplyNotice.first(
            in: timeline.threadReplies.echoes,
            isSendQueueEnabled: timeline.threadReplies.isSendQueueEnabled,
            shownThreadRoot: shownThreadRoot
        )
    }

    var body: some View {
        if let notice {
            UI.ThreadReplyNoticeView(
                retry: { Task { await timeline.threadReplies.retry(notice) } },
                openThread: canOpenThread ? { windowState.focusThread(rootEventId: notice.threadRoot) } : nil,
                discard: { Task { await timeline.threadReplies.discard(notice) } }
            )
            .padding(.horizontal)
        }
    }
}
