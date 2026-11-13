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
    ///
    /// A merged chat's timeline (MATRIX-142) shows rows of several member
    /// rooms, and each member `LiveTimeline` has its own request channel, so
    /// the presenter keeps one cursor per room timeline.
    @MainActor
    final class TimelineReactionPickerPresenter: NSObject, NSPopoverDelegate {
        /// Identifies one request: the room timeline it came from and its
        /// nonce in that timeline's channel.
        struct RequestToken: Equatable {
            let timeline: ObjectIdentifier
            let nonce: Int
        }

        /// The requests this view has taken from each room timeline, by the
        /// timeline's identity.
        private var cursors: [ObjectIdentifier: NoncedRequestCursor]
        /// The request taken last. A newer one retires it.
        private var newestRequest: RequestToken?

        /// The open popover, or nil.
        private(set) var popover: NSPopover? {
            didSet {
                if (oldValue == nil) != (popover == nil) {
                    onOpenChange?(popover != nil)
                }
            }
        }

        /// Called when the picker opens (true) or closes (false). The
        /// floating hover bar hides while the picker is open (MATRIX-145).
        var onOpenChange: (@MainActor (Bool) -> Void)?

        /// - Parameter timelines: The room timelines whose requests the
        ///   controller serves. Each one's latest request when the controller
        ///   starts counts as handled.
        init(startingAt timelines: [LiveTimeline]) {
            var cursors: [ObjectIdentifier: NoncedRequestCursor] = [:]
            for timeline in timelines {
                cursors[ObjectIdentifier(timeline)] = NoncedRequestCursor(startingAt: timeline.reactionPickerRequests.latest)
            }
            self.cursors = cursors
            super.init()
        }

        /// Takes `timeline`'s latest request if this presenter has not taken
        /// it yet, and makes it the newest one.
        ///
        /// - Returns: The request and its token, or nil for a request already
        ///   taken.
        func take(from timeline: LiveTimeline) -> (request: ReactionPickerRequest, token: RequestToken)? {
            let key = ObjectIdentifier(timeline)
            var cursor = cursors[key] ?? NoncedRequestCursor(startingAt: nil as NoncedRequest<ReactionPickerRequest>?)
            guard let request = cursor.take(timeline.reactionPickerRequests.latest) else { return nil }
            cursors[key] = cursor
            let token = RequestToken(timeline: key, nonce: cursor.handledNonce)
            newestRequest = token
            return (request, token)
        }

        /// Whether `token` is still the newest request. A row scroll runs
        /// before the popover shows, and a newer request in that time
        /// retires the older one.
        func isCurrent(_ token: RequestToken) -> Bool {
            newestRequest == token
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
        /// The room the reaction goes to. Its workspace's image packs are
        /// the custom emoji of the picker (MATRIX-155).
        let roomId: String
        let onClose: @MainActor () -> Void
        let onPick: @MainActor (String) -> Void

        var body: some View {
            UI.ReactionPickerView(
                catalog: .bundled,
                recents: client?.recentEmojis.emojis ?? [],
                packs: client?.imagePacks.packs(forRoom: roomId) ?? [],
                imageLoader: client,
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
            token: TimelineReactionPickerPresenter.RequestToken
        ) {
            let barAnchor = hoverBarPickerAnchor(
                forMessageKey: request.eventId.id,
                buttonsAfter: request.hoverButtonsAfterPicker
            )
            reactionPicker.close()
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
            token: TimelineReactionPickerPresenter.RequestToken,
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
