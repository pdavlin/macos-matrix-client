// The timeline spike compiles the controller without Core (see spike/GATE.md),
// and this file is not linked into the spike, so the controller reaches it only
// under `canImport(Core)`.
#if canImport(Core)
    import AppKit
    import Core
    import Models
    import SwiftUI

    // MATRIX-138: a popover on a timeline row is an AppKit popover, owned by
    // the timeline controller.
    //
    // A SwiftUI `.popover` on a row in the timeline table did not open (the
    // cause is not confirmed). The rows send a request through a channel on
    // their `LiveTimeline`; the controller finds the row, scrolls it into view
    // if needed, and shows one `NSPopover` on it. The reaction picker
    // (MATRIX-138) and the edit history (MATRIX-209) work this way.

    /// Identifies one request: the room timeline it came from and its nonce
    /// in that timeline's channel.
    struct TimelinePopoverRequestToken: Equatable {
        let timeline: ObjectIdentifier
        let nonce: Int
    }

    /// Owns one kind of popover of one timeline.
    ///
    /// One popover at a time: a new request closes the open one. The
    /// presenter also remembers which requests it took, so a timeline view
    /// made again (the user comes back to a room) does not replay an old one.
    ///
    /// A merged chat's timeline (MATRIX-142) shows rows of several member
    /// rooms, and each member `LiveTimeline` has its own request channel, so
    /// the presenter keeps one cursor per room timeline.
    @MainActor
    final class TimelinePopoverPresenter<Request>: NSObject, NSPopoverDelegate {
        /// The channel of each room timeline that this presenter serves.
        private let requests: KeyPath<LiveTimeline, NoncedRequestChannel<Request>>
        /// The requests this view has taken from each room timeline, by the
        /// timeline's identity.
        private var cursors: [ObjectIdentifier: NoncedRequestCursor]
        /// The request taken last. A newer one retires it.
        private var newestRequest: TimelinePopoverRequestToken?

        /// The open popover, or nil.
        private(set) var popover: NSPopover? {
            didSet {
                if (oldValue == nil) != (popover == nil) {
                    onOpenChange?(popover != nil)
                }
            }
        }

        /// Called when the popover opens (true) or closes (false). The
        /// floating hover bar hides while the reaction picker is open
        /// (MATRIX-145).
        var onOpenChange: (@MainActor (Bool) -> Void)?

        /// - Parameters:
        ///   - requests: The request channel of a room timeline.
        ///   - timelines: The room timelines whose requests the controller
        ///     serves. Each one's latest request when the controller starts
        ///     counts as handled.
        init(requests: KeyPath<LiveTimeline, NoncedRequestChannel<Request>>, startingAt timelines: [LiveTimeline]) {
            self.requests = requests
            var cursors: [ObjectIdentifier: NoncedRequestCursor] = [:]
            for timeline in timelines {
                cursors[ObjectIdentifier(timeline)] = NoncedRequestCursor(startingAt: timeline[keyPath: requests].latest)
            }
            self.cursors = cursors
            super.init()
        }

        /// Takes `timeline`'s latest request if this presenter has not taken
        /// it yet, and makes it the newest one.
        ///
        /// - Returns: The request and its token, or nil for a request already
        ///   taken.
        func take(from timeline: LiveTimeline) -> (request: Request, token: TimelinePopoverRequestToken)? {
            let key = ObjectIdentifier(timeline)
            var cursor = cursors[key] ?? NoncedRequestCursor(startingAt: nil as NoncedRequest<Request>?)
            guard let request = cursor.take(timeline[keyPath: requests].latest) else { return nil }
            cursors[key] = cursor
            let token = TimelinePopoverRequestToken(timeline: key, nonce: cursor.handledNonce)
            newestRequest = token
            return (request, token)
        }

        /// Whether `token` is still the newest request. A row scroll runs
        /// before the popover shows, and a newer request in that time
        /// retires the older one.
        func isCurrent(_ token: TimelinePopoverRequestToken) -> Bool {
            newestRequest == token
        }

        /// Shows `content` in a transient popover that hangs from `rect`.
        ///
        /// - Parameters:
        ///   - content: The popover's view.
        ///   - rect: The anchor, in `view`'s coordinates.
        ///   - view: The view the popover points at.
        ///   - preferredEdge: The edge of `rect` the popover opens from. AppKit
        ///     uses another edge if the popover does not fit there.
        func show(_ content: some View, relativeTo rect: CGRect, of view: NSView, preferredEdge: NSRectEdge) {
            close()
            let host = NSHostingController(rootView: content)
            // The popover takes its size from the content's ideal size.
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

    extension TimelineViewController {
        /// Observes the requests of every row popover.
        func listenForPopoverRequests() {
            listenForReactionPickerRequests()
            listenForEditHistoryRequests()
        }

        /// Closes the row popovers. One shows at a time.
        func closePopovers() {
            reactionPicker.close()
            editHistory.close()
        }
    }

    extension NSRectEdge {
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
