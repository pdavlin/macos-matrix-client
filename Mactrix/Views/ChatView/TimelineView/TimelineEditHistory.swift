// The timeline spike compiles the controller without Core (see spike/GATE.md),
// and this file is not linked into the spike, so the controller reaches it only
// under `canImport(Core)`.
#if canImport(Core)
    import AppKit
    import Core
    import MatrixRustSDK
    import Models
    import OSLog
    import SwiftUI
    import Tokens
    import UI

    // MATRIX-209: the edit history of a message as an AppKit popover, owned
    // by the timeline controller (`TimelinePopoverPresenter`). The rows send
    // a request through `LiveTimeline.requestEditHistory(forEventId:)`; the
    // controller shows the popover on the row.

    /// The popover's content: reads the versions from the SDK when it shows,
    /// and draws each message body as the timeline row draws it.
    private struct TimelineEditHistoryContent: View {
        let timeline: LiveTimeline
        let eventId: String
        let imageLoader: (any UI.ImageLoader)?

        @AppStorage(TypographyToken.fontSizeStorageKey) private var fontSize = TypographyToken.defaultBaseFontSize
        @State private var state: EditHistoryState<MatrixRustSDK.MessageContent> = .loading

        private var typography: TimelineTypography {
            TimelineTypography(base: CGFloat(fontSize))
        }

        var body: some View {
            UI.EditHistoryView(state: state) { message in
                TimelineEditHistoryBody(content: message, imageLoader: imageLoader)
                    .font(.system(size: typography.base))
            }
            .environment(\.timelineTypography, typography)
            .task(id: eventId) {
                state = await timeline.editHistory(of: eventId)
            }
        }
    }

    /// One version's message body. Text, notices, and emotes go through the
    /// timeline's text rendering (`FormattedBodyView`). Other message types
    /// show their plain body, which is the caption or the file name of a
    /// media message.
    private struct TimelineEditHistoryBody: View {
        let content: MatrixRustSDK.MessageContent
        let imageLoader: (any UI.ImageLoader)?

        var body: some View {
            switch content.msgType {
            case let .text(content: text):
                FormattedBodyView(messageContent: text, imageLoader: imageLoader)
            case let .notice(content: notice):
                FormattedBodyView(messageContent: notice, imageLoader: imageLoader)
            case let .emote(content: emote):
                FormattedBodyView(messageContent: emote, imageLoader: imageLoader)
            case .image, .video, .audio, .file, .gallery, .location, .other:
                Text(content.displayBody)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    extension TimelineViewController {
        /// Observes the edit history requests of every room timeline of the
        /// source (one, or each member of a merged chat).
        func listenForEditHistoryRequests() {
            for timeline in source.actionTimelines {
                listenForEditHistoryRequests(on: timeline)
            }
        }

        /// Observes one room timeline's edit history requests and serves
        /// each new one. Re-arms itself on every change, like the reaction
        /// picker listener. The timeline is held weakly.
        private func listenForEditHistoryRequests(on timeline: LiveTimeline) {
            withObservationTracking {
                _ = timeline.editHistoryRequests.latest
            } onChange: { [weak self, weak timeline] in
                Task { @MainActor [weak self, weak timeline] in
                    guard let self, let timeline else { return }
                    listenForEditHistoryRequests(on: timeline)
                }
            }

            guard let taken = editHistory.take(from: timeline) else { return }
            presentEditHistory(taken.request, from: timeline, token: taken.token)
        }

        /// Closes an open popover, finds the request's row, scrolls it into
        /// view if needed, then shows the edit history on it.
        ///
        /// - Parameter timeline: The room timeline that sent the request: the
        ///   SDK reads the versions in its room (MATRIX-142).
        private func presentEditHistory(
            _ request: EditHistoryRequest,
            from timeline: LiveTimeline,
            token: TimelinePopoverRequestToken
        ) {
            closePopovers()
            let event = TimelineEventReference(eventId: .eventId(eventId: request.eventId), roomId: timeline.room.id)
            guard let rowIndex = rowIndex(of: event) else {
                Logger.timelineTableView.error("edit history: no row for \(request.eventId)")
                return
            }
            // Identity, not index: rows can renumber during the scroll.
            let rowId = timelineRows[rowIndex].uniqueId
            tableView.animateRowToVisible(rowIndex) { [weak self, weak timeline] in
                guard let timeline else { return }
                self?.showEditHistory(request, from: timeline, onRowId: rowId, token: token)
            }
        }

        /// Shows the popover on the row once it is in view. It hangs from the
        /// top of the row, where a reaction picker opened from a menu hangs.
        private func showEditHistory(
            _ request: EditHistoryRequest,
            from timeline: LiveTimeline,
            onRowId rowId: String,
            token: TimelinePopoverRequestToken
        ) {
            guard editHistory.isCurrent(token) else { return }
            guard let rowIndex = timelineRows.firstIndex(where: { $0.uniqueId == rowId }),
                  let rowView = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false),
                  let anchor = HoverActionBarGeometry.anchorRect(
                      in: rowView.bounds,
                      visibleRect: rowView.visibleRect,
                      isFlipped: rowView.isFlipped,
                      buttonsAfter: nil
                  )
            else {
                Logger.timelineTableView.error("edit history: the row for \(request.eventId) does not show")
                return
            }

            let content = TimelineEditHistoryContent(
                timeline: timeline,
                eventId: request.eventId,
                imageLoader: coordinator.appState.matrixClient
            )
            editHistory.show(
                content,
                relativeTo: anchor,
                of: rowView,
                preferredEdge: NSRectEdge(HoverActionBarGeometry.topEdge(isFlipped: rowView.isFlipped))
            )
        }
    }
#endif
