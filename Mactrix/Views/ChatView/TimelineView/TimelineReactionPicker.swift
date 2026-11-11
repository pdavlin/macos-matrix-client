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
    // timeline controller.
    //
    // A SwiftUI `.popover` on a row in the timeline table did not open (the
    // cause is not confirmed). The rows now send a request through
    // `LiveTimeline.requestReactionPicker(for:hoverButtonsAfterPicker:)`; the
    // controller finds the row, scrolls it into view if needed, and shows one
    // `NSPopover` over the hover row's picker button.

    /// Owns the reaction picker popover of one timeline.
    ///
    /// One popover at a time: a new request closes the open one. The
    /// presenter also remembers which requests it took, so a timeline view
    /// made again (the user comes back to a room) does not replay an old one.
    @MainActor
    final class TimelineReactionPickerPresenter: NSObject, NSPopoverDelegate {
        /// The requests this timeline has taken from `LiveTimeline`.
        var requests: NoncedRequestCursor

        /// The open popover, or nil.
        private(set) var popover: NSPopover?

        /// - Parameter current: The timeline's latest request when the
        ///   controller starts. It counts as handled.
        init(startingAt current: NoncedRequest<ReactionPickerRequest>?) {
            requests = NoncedRequestCursor(startingAt: current)
            super.init()
        }

        /// Whether `nonce` is still the newest request. A row scroll runs
        /// before the popover shows, and a newer request in that time
        /// retires the older one.
        func isCurrent(nonce: Int) -> Bool {
            requests.handledNonce == nonce
        }

        /// Shows `content` in a transient popover that hangs from `rect`.
        ///
        /// - Parameters:
        ///   - content: The picker view.
        ///   - rect: The anchor, in `view`'s coordinates.
        ///   - view: The row view the popover points at.
        ///   - preferredEdge: The edge of `rect` the popover opens from. AppKit
        ///     uses another edge if the popover does not fit there.
        func show(_ content: some View, relativeTo rect: CGRect, of view: NSView, preferredEdge: NSRectEdge) {
            close()
            let host = NSHostingController(rootView: content)
            // The popover takes its size from the picker's ideal size.
            host.sizingOptions = [.preferredContentSize]

            let popover = NSPopover()
            popover.behavior = .transient
            popover.contentViewController = host
            popover.delegate = self
            self.popover = popover
            popover.show(relativeTo: rect, of: view, preferredEdge: preferredEdge)
        }

        /// Closes the open popover at once, if there is one.
        func close() {
            guard let popover else { return }
            self.popover = nil
            popover.close()
        }

        func popoverDidClose(_ notification: Notification) {
            guard let closed = notification.object as? NSPopover, closed === popover else { return }
            popover = nil
        }
    }

    /// The picker inside the popover. A view of its own so the recent row
    /// follows the account's list: the list can finish loading after the
    /// picker opens, and the body reads it through observation.
    private struct TimelineReactionPickerContent: View {
        let client: MatrixClient?
        let onClose: @MainActor () -> Void
        let onPick: @MainActor (String) -> Void

        var body: some View {
            UI.ReactionPickerView(
                catalog: .bundled,
                recents: client?.recentEmojis.emojis ?? [],
                onClose: onClose,
                onPick: onPick
            )
        }
    }

    extension TimelineViewController {
        /// Observes the timeline's reaction picker requests and serves each
        /// new one. Re-arms itself on every change, like the focus and
        /// scroll-to-bottom listeners.
        func listenForReactionPickerRequests() {
            let latest = withObservationTracking {
                timeline.reactionPickerRequests.latest
            } onChange: { [weak self] in
                Task { @MainActor in self?.listenForReactionPickerRequests() }
            }

            guard let request = reactionPicker.requests.take(latest) else { return }
            presentReactionPicker(request, nonce: reactionPicker.requests.handledNonce)
        }

        /// Closes an open picker, finds the request's row, scrolls it into
        /// view if needed, then shows the picker on it.
        private func presentReactionPicker(_ request: ReactionPickerRequest, nonce: Int) {
            reactionPicker.close()
            guard let rowIndex = rowIndex(forEvent: request.eventId) else {
                Logger.timelineTableView.error("reaction picker: no row for \(request.eventId.id)")
                return
            }
            // Identity, not index: rows can renumber during the scroll.
            let rowId = timelineRows[rowIndex].uniqueId
            tableView.animateRowToVisible(rowIndex) { [weak self] in
                self?.showReactionPicker(request, onRowId: rowId, nonce: nonce)
            }
        }

        /// Shows the picker on the row once it is in view.
        private func showReactionPicker(_ request: ReactionPickerRequest, onRowId rowId: String, nonce: Int) {
            guard reactionPicker.isCurrent(nonce: nonce) else { return }
            guard let rowIndex = timelineRows.firstIndex(where: { $0.uniqueId == rowId }),
                  let rowView = tableView.view(atColumn: 0, row: rowIndex, makeIfNecessary: false)
            else {
                Logger.timelineTableView.error("reaction picker: the row for \(request.eventId.id) is not on screen")
                return
            }
            guard let anchor = HoverActionBarGeometry.anchorRect(
                in: rowView.bounds,
                visibleRect: rowView.visibleRect,
                isFlipped: rowView.isFlipped,
                buttonsAfter: request.hoverButtonsAfterPicker
            ) else {
                Logger.timelineTableView.error("reaction picker: the row for \(request.eventId.id) does not show")
                return
            }

            let timeline = timeline
            let client = coordinator.appState.matrixClient
            let itemId = request.eventId
            let content = TimelineReactionPickerContent(
                client: client,
                onClose: { [weak reactionPicker] in reactionPicker?.close() },
                onPick: { emoji in
                    Task { await timeline.toggleReaction(key: emoji, on: itemId, recordingUseIn: client) }
                }
            )
            reactionPicker.show(
                content,
                relativeTo: anchor,
                of: rowView,
                preferredEdge: NSRectEdge(HoverActionBarGeometry.topEdge(isFlipped: rowView.isFlipped))
            )
        }
    }

    private extension NSRectEdge {
        /// The AppKit edge for a Core Graphics edge. The library computes the
        /// edge as `CGRectEdge` so it stays free of AppKit.
        init(_ edge: CGRectEdge) {
            switch edge {
            case .minXEdge: self = .minX
            case .minYEdge: self = .minY
            case .maxXEdge: self = .maxX
            case .maxYEdge: self = .maxY
            @unknown default: self = .maxY
            }
        }
    }
#endif
