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
    import UI

    // MATRIX-138: the reaction picker as an AppKit popover, owned by the
    // timeline controller (`TimelinePopoverPresenter`). The rows send a
    // request through
    // `LiveTimeline.requestReactionPicker(for:hoverButtonsAfterPicker:)`; the
    // controller shows the picker over the hover row's picker button.

    /// The picker inside the popover. A view of its own so the recent row
    /// follows the account's list: the list can finish loading after the
    /// picker opens, and the body reads it through observation.
    private struct TimelineReactionPickerContent: View {
        let client: MatrixClient?
        /// The room the reaction goes to. Its workspace's image packs are
        /// the custom emoji of the picker (MATRIX-155).
        let roomId: String
        let onClose: @MainActor () -> Void
        let onPick: @MainActor (String) -> Void

        /// The "Refresh Custom Emoji" button of the pack section
        /// (MATRIX-161). The status read is observed, so the header follows
        /// the refresh; so are the packs, which a refresh or a learned emoji
        /// changes while the picker is open.
        private var packRefresh: UI.ImagePackRefreshControl? {
            guard let client else { return nil }
            return UI.ImagePackRefreshControl(status: client.imagePacks.refreshStatusByRoom[roomId]) { [roomId] in
                client.refreshImagePacks(forRoom: roomId)
            }
        }

        var body: some View {
            UI.ReactionPickerView(
                catalog: .bundled,
                recents: client?.recentEmojis.emojis ?? [],
                packs: client?.imagePacks.packs(forRoom: roomId) ?? [],
                imageLoader: client,
                packRefresh: packRefresh,
                onClose: onClose,
                onPick: onPick
            )
        }
    }

    extension TimelineViewController {
        /// Observes the reaction picker requests of every room timeline of
        /// the source (one, or each member of a merged chat).
        func listenForReactionPickerRequests() {
            for timeline in source.actionTimelines {
                // MATRIX-155: read the custom emoji of each room's workspace
                // now, so the picker has them when it opens.
                coordinator.appState.matrixClient?.loadImagePacks(forRoom: timeline.room.id)
                listenForReactionPickerRequests(on: timeline)
            }
        }

        /// Observes one room timeline's reaction picker requests and serves
        /// each new one. Re-arms itself on every change, like the focus and
        /// scroll-to-bottom listeners. The timeline is held weakly: the
        /// tracking closure stays in its observation registrar until the
        /// next change.
        private func listenForReactionPickerRequests(on timeline: LiveTimeline) {
            withObservationTracking {
                _ = timeline.reactionPickerRequests.latest
            } onChange: { [weak self, weak timeline] in
                Task { @MainActor [weak self, weak timeline] in
                    guard let self, let timeline else { return }
                    listenForReactionPickerRequests(on: timeline)
                }
            }

            guard let taken = reactionPicker.take(from: timeline) else { return }
            presentReactionPicker(taken.request, from: timeline, token: taken.token)
        }

        /// Closes an open picker, finds the request's row, scrolls it into
        /// view if needed, then shows the picker on it.
        ///
        /// When the floating hover bar shows for the message (the person
        /// clicked its picker button), the picker hangs from that button
        /// (MATRIX-145). The anchor is taken now, in the table's coordinates,
        /// before the picker hides the bar; a scroll moves the anchor with
        /// the row. A request from a menu, with no bar, hangs from the row.
        ///
        /// - Parameter timeline: The room timeline that sent the request: the
        ///   reaction goes to its room (MATRIX-142).
        private func presentReactionPicker(
            _ request: ReactionPickerRequest,
            from timeline: LiveTimeline,
            token: TimelinePopoverRequestToken
        ) {
            let barAnchor = hoverBarPickerAnchor(
                forMessageKey: request.eventId.id,
                buttonsAfter: request.hoverButtonsAfterPicker
            )
            closePopovers()
            let event = TimelineEventReference(eventId: request.eventId, roomId: timeline.room.id)
            guard let rowIndex = rowIndex(of: event) else {
                Logger.timelineTableView.error("reaction picker: no row for \(request.eventId.id)")
                return
            }
            // Identity, not index: rows can renumber during the scroll.
            let rowId = timelineRows[rowIndex].uniqueId
            tableView.animateRowToVisible(rowIndex) { [weak self, weak timeline] in
                guard let timeline else { return }
                self?.showReactionPicker(request, from: timeline, onRowId: rowId, token: token, barAnchor: barAnchor)
            }
        }

        /// Shows the picker on the row once it is in view.
        ///
        /// - Parameter barAnchor: The hover bar's picker button in the
        ///   table's coordinates, or nil to hang the picker from the row.
        private func showReactionPicker(
            _ request: ReactionPickerRequest,
            from timeline: LiveTimeline,
            onRowId rowId: String,
            token: TimelinePopoverRequestToken,
            barAnchor: CGRect?
        ) {
            guard reactionPicker.isCurrent(token) else { return }
            guard let rowIndex = timelineRows.firstIndex(where: { $0.uniqueId == rowId }),
                  let rowView = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false)
            else {
                Logger.timelineTableView.error("reaction picker: the row for \(request.eventId.id) is not on screen")
                return
            }
            let anchorView: NSView = barAnchor == nil ? rowView : tableView
            guard let anchor = barAnchor ?? HoverActionBarGeometry.anchorRect(
                in: rowView.bounds,
                visibleRect: rowView.visibleRect,
                isFlipped: rowView.isFlipped,
                buttonsAfter: request.hoverButtonsAfterPicker
            ) else {
                Logger.timelineTableView.error("reaction picker: the row for \(request.eventId.id) does not show")
                return
            }

            let client = coordinator.appState.matrixClient
            // Again here: the SDK finds no parent space for a room until its
            // space graph is ready, and the store does not keep that answer.
            // The store also reads a space again when its last read is old
            // (MATRIX-161), so an emoji import shows without a restart.
            client?.loadImagePacks(forRoom: timeline.room.id)
            let itemId = request.eventId
            let content = TimelineReactionPickerContent(
                client: client,
                roomId: timeline.room.id,
                onClose: { [weak reactionPicker] in reactionPicker?.close() },
                onPick: { emoji in
                    Task { await timeline.toggleReaction(key: emoji, on: itemId, recordingUseIn: client) }
                }
            )
            reactionPicker.show(
                content,
                relativeTo: anchor,
                of: anchorView,
                preferredEdge: NSRectEdge(HoverActionBarGeometry.topEdge(isFlipped: anchorView.isFlipped))
            )
        }
    }
#endif
