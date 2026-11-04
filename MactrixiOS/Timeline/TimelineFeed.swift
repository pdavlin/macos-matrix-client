import Models

/// One display-ordered change with the rows it introduced (MATRIX-85).
///
/// The row-model twin of `TimelineDisplayUpdate`: the container works on
/// `TimelineRow`s only, so the SDK mapping happens once, in the feed.
struct TimelineRowChange {
    let change: TimelineDisplayChange
    /// Inserted or replacement rows, in display order. Empty for removals and
    /// resets.
    let rows: [TimelineRow]
}

/// What the iOS timeline container reads and drives (MATRIX-85).
///
/// `LiveTimelineFeed` adapts `LiveTimeline`; a DEBUG fixture feed drives the
/// same container without an account. The container never touches the SDK,
/// so everything it needs crosses this seam as row models.
@MainActor
protocol TimelineFeed: AnyObject {
    /// Every item row, newest first. Decoration rows are the container's own.
    var displayRows: [TimelineRow] { get }

    /// Hands over every change since the last call, and clears the queue.
    func drainRowChanges() -> [TimelineRowChange]

    /// Reads every observable property whose change must reach the container.
    ///
    /// The container calls this inside `withObservationTracking`, so a write
    /// to any property read here schedules one container update.
    func touchObservedState()

    /// Display names of the users typing now (D-3).
    var typingNames: [String] { get }
    /// True while a back-pagination is in flight (D-2).
    var isPaginating: Bool { get }
    /// The message of the last failed back-pagination, or nil.
    var paginationFailure: String? { get }

    /// Whether the view sits at (or near) the newest message.
    var isAtBottom: Bool { get }
    /// Messages from others that arrived while scrolled up.
    var unseenArrivals: Int { get }
    /// Monotonic count of scroll-to-bottom requests.
    var scrollToBottomRequests: Int { get }

    /// Identity of the current focus request (an event to scroll to), or nil.
    var focusRequestId: String? { get }
    /// Item index of the focused event, once the event has arrived.
    func itemIndexOfFocusRequest() -> Int?

    func setAtBottom(_ atBottom: Bool)
    func requestScrollToBottom()
    func fetchOlderMessages() async
    func retryPagination()
}
