import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Tokens
import UI

/// The SwiftUI view one timeline row renders, both in the table and in the
/// offscreen measurement host. One view for both, so a measured height is the
/// height the row draws at.
struct TimelineItemRowView: View {
    let row: TimelineRow
    let timeline: LiveTimeline?

    let appState: AppState
    let windowState: WindowState

    @AppStorage(TypographyToken.fontSizeStorageKey) private var fontSize = TypographyToken.defaultBaseFontSize

    init(row: TimelineRow, timeline: LiveTimeline?, coordinator: TimelineViewRepresentable.Coordinator) {
        self.row = row
        self.timeline = timeline
        self.appState = coordinator.appState
        self.windowState = coordinator.windowState
    }

    /// D-3: read receipts render in direct rooms only. A group room's receipt
    /// pile churns on every member's read and tells the reader nothing.
    private var showsReadReceipts: Bool {
        timeline?.room.roomInfo?.isDirect == true
    }

    @ViewBuilder
    var contentView: some View {
        switch row {
        case let .message(_, event, _, _):
            if let event = event as? MatrixRustSDK.EventTimelineItem, case let .msgLike(content: content) = event.content {
                ChatMessageView(timeline: timeline, event: event, msg: content, includeProfileHeader: true)
            } else {
                logAndShow("Message", log: "Message row did not resolve to an SDK event with msg-like content")
            }
        case let .state(_, event, name):
            if let event = event as? MatrixRustSDK.EventTimelineItem {
                UI.GenericEventView(event: event, name: name)
            } else {
                logAndShow(name, log: "State row did not resolve to an SDK event")
            }
        case let .virtual(_, item):
            UI.VirtualItemView(item: item)
        case let .typingIndicator(_, names):
            UI.TypingIndicatorRow(names: names)
        case .paginationActivity:
            UI.PaginationActivityRow()
        case let .paginationFailure(_, message):
            UI.PaginationFailureRow(message: message) {
                timeline?.retryPagination()
            }
        case .unsupported:
            // Height is clamped to 1pt by the measurement layer, so an
            // unrenderable item occupies a row without showing anything.
            EmptyView()
        }
    }

    private func logAndShow(_ text: String, log message: String) -> some View {
        Logger.timelineRowMapping.warning("\(message, privacy: .public)")
        return Text(text)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                contentView
                    .environment(appState)
                    .environment(windowState)
            }
        }
        .environment(\.timelineTypography, TimelineTypography(base: CGFloat(fontSize)))
        .environment(\.timelineShowsReadReceipts, showsReadReceipts)
    }
}
