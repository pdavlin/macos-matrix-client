import Models
import SwiftUI

extension View {
    /// DEBUG builds launched with `-TimelineFixture` show the timeline
    /// container on fake rows instead of this view, for simulator smoke tests
    /// without an account (hard rule 3). Release builds return the view as is.
    @ViewBuilder
    func timelineFixtureOverride() -> some View {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-TimelineFixture") {
                TimelineFixtureScreen()
            } else {
                self
            }
        #else
            self
        #endif
    }
}

#if DEBUG
    /// The container on a scripted feed: sender runs, day dividers, a read
    /// marker, back-pagination, and a stream of arrivals, reaction re-tallies,
    /// and edits that exercise the drain and the anchor.
    struct TimelineFixtureScreen: View {
        @State private var feed = TimelineFixtureFeed()

        var body: some View {
            NavigationStack {
                TimelineContainer(feed: feed, timeline: nil, imageLoader: nil, ownUserId: "@me:fixture", showsReadReceipts: false)
                    .navigationTitle("Timeline fixture")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .task { await feed.run() }
        }
    }

    /// A fake event with its own body and reaction pills.
    struct TimelineFixtureEvent: TimelineTextEvent {
        let sender: String
        let name: String
        let date: Date
        let body: String
        let reactionPills: [TimelineReactionPill]

        var isRemote: Bool { true }
        var senderProfileDetails: ProfileDetails {
            .ready(displayName: name, displayNameAmbiguous: false, avatarUrl: nil)
        }

        var isOwn: Bool { sender == "@me:fixture" }
        var isEditable: Bool { false }
        var sendState: LocalSendState? { nil }
        var localCreatedAt: UInt64? { nil }
        var userReadReceipts: [String: Receipt] { [:] }
        var canBeRepliedTo: Bool { false }
        var userId: String { sender }
        var displayName: String? { name }
        var avatarUrl: String? { nil }

        var row: TimelineRow {
            .message(
                uniqueId: "fixture.\(date.timeIntervalSince1970)",
                event: self,
                kind: .text,
                heightFingerprint: TimelineRowHeightFingerprint(
                    body: MessageBodyGeometry(variant: "text", text: body),
                    senderName: name,
                    reactions: ReactionStripGeometry(
                        reactions: reactionPills.lazy.map { (key: $0.key, senderCount: $0.senders.count) },
                        hasReadReceipts: false
                    )
                )
            )
        }

        func with(body: String? = nil, reactionPills: [TimelineReactionPill]? = nil) -> TimelineFixtureEvent {
            TimelineFixtureEvent(
                sender: sender,
                name: name,
                date: date,
                body: body ?? self.body,
                reactionPills: reactionPills ?? self.reactionPills
            )
        }
    }

    @MainActor @Observable
    final class TimelineFixtureFeed: TimelineFeed {
        private static let senders: [(id: String, name: String)] = [
            ("@ada:fixture", "Ada Lovelace"),
            ("@bob:fixture", "Bob Kahn"),
            ("@me:fixture", "Me"),
        ]
        private static let bodies = [
            "Morning.",
            "Did the bridge come back after the restart?",
            "Yes, it reconnected and the backlog is flowing again. The Slack side took a minute to catch up "
                + "but every channel I checked has the messages from overnight.",
            "Nice.",
            "Lunch?",
            "I will push the fix after the review. It touches the timeline drain, so it needs a careful look "
                + "at the frame budget numbers before it lands.",
            "👍",
            "Can you check the pinned version first?",
        ]
        private static let pageSize = 25
        private static let maximumPages = 4

        /// Bumped on every change; the container tracks it.
        private var generation = 0
        @ObservationIgnored private var pending: [TimelineRowChange] = []
        @ObservationIgnored private var items: [TimelineRow] = []
        @ObservationIgnored private var events: [String: TimelineFixtureEvent] = [:]
        @ObservationIgnored private var sequence = 0
        @ObservationIgnored private var oldestDate = Date.now
        @ObservationIgnored private var pagesLoaded = 0

        private(set) var typingNames: [String] = []
        private(set) var isPaginating = false
        private(set) var paginationFailure: String?
        private(set) var isAtBottom = true
        private(set) var unseenArrivals = 0
        private(set) var scrollToBottomRequests = 0

        init() {
            items = (0 ..< 30).map { _ in olderRow() }
            items.insert(.virtual(uniqueId: "fixture.readMarker", item: .readMarker), at: 6)
        }

        var displayRows: [TimelineRow] { items }

        func drainRowChanges() -> [TimelineRowChange] {
            defer { pending.removeAll() }
            return pending
        }

        func touchObservedState() {
            _ = generation
            _ = typingNames
            _ = isPaginating
            _ = paginationFailure
            _ = scrollToBottomRequests
        }

        var focusRequestId: String? { nil }
        func itemIndexOfFocusRequest() -> Int? {
            nil
        }

        func setAtBottom(_ atBottom: Bool) {
            guard isAtBottom != atBottom else { return }
            isAtBottom = atBottom
            if atBottom { unseenArrivals = 0 }
        }

        func requestScrollToBottom() {
            scrollToBottomRequests += 1
            setAtBottom(true)
        }

        func fetchOlderMessages() async {
            guard !isPaginating, pagesLoaded < Self.maximumPages else { return }
            isPaginating = true
            try? await Task.sleep(for: .milliseconds(700))
            pagesLoaded += 1
            var page = (0 ..< Self.pageSize).map { _ in olderRow() }
            if pagesLoaded == Self.maximumPages {
                page.append(.virtual(uniqueId: "fixture.start", item: .timelineStart))
            }
            record(.insert(index: items.count, count: page.count), rows: page)
            items.append(contentsOf: page)
            isPaginating = false
        }

        func retryPagination() {
            paginationFailure = nil
        }

        /// The scripted stream: an arrival, a typing burst, a re-tally (height
        /// neutral), a new pill (height change), and an edit (height change).
        func run() async {
            var step = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                step += 1
                switch step % 5 {
                case 0:
                    typingNames = []
                    arrive()
                case 1:
                    typingNames = ["Bob Kahn"]
                case 2:
                    react(at: 1, adding: false)
                case 3:
                    react(at: 2, adding: true)
                default:
                    edit(at: 3)
                }
            }
        }

        private func arrive() {
            sequence += 1
            let sender = Self.senders[sequence % 2]
            let event = TimelineFixtureEvent(
                sender: sender.id,
                name: sender.name,
                date: .now,
                body: Self.bodies[sequence % Self.bodies.count],
                reactionPills: []
            )
            let row = remember(event)
            items.insert(row, at: 0)
            record(.insert(index: 0, count: 1), rows: [row])
            if !isAtBottom { unseenArrivals += 1 }
        }

        private func react(at index: Int, adding: Bool) {
            guard let event = event(at: index) else { return }
            var pills = event.reactionPills
            let tally = (pills.first?.senders.count ?? 0) + 1
            let senders = (0 ..< tally).map { TimelineReactionPill.Sender(senderId: "@u\($0):fixture", date: .now) }
            if pills.isEmpty || adding {
                pills.append(TimelineReactionPill(key: adding ? "🎉" : "👍", senders: senders))
            } else {
                pills[0] = TimelineReactionPill(key: pills[0].key, senders: senders)
            }
            replace(at: index, with: event.with(reactionPills: pills))
        }

        private func edit(at index: Int) {
            guard let event = event(at: index) else { return }
            replace(at: index, with: event.with(body: event.body + " (edited, and longer than it was before)"))
        }

        private func event(at index: Int) -> TimelineFixtureEvent? {
            guard items.indices.contains(index) else { return nil }
            return events[items[index].uniqueId]
        }

        private func replace(at index: Int, with event: TimelineFixtureEvent) {
            let row = remember(event)
            items[index] = row
            record(.update(index: index), rows: [row])
        }

        /// One row older than every row so far, with a day divider every
        /// twelve rows.
        private func olderRow() -> TimelineRow {
            sequence += 1
            oldestDate -= 60 * 7
            if sequence.isMultiple(of: 12) {
                return .virtual(uniqueId: "fixture.day.\(sequence)", item: .dateDivider(date: oldestDate))
            }
            // Runs of two or three from one sender, so grouping shows.
            let sender = Self.senders[(sequence / 3) % Self.senders.count]
            let event = TimelineFixtureEvent(
                sender: sender.id,
                name: sender.name,
                date: oldestDate,
                body: Self.bodies[sequence % Self.bodies.count],
                reactionPills: sequence.isMultiple(of: 5)
                    ? [TimelineReactionPill(key: "👍", senders: [.init(senderId: "@ada:fixture", date: .now)])]
                    : []
            )
            return remember(event)
        }

        private func remember(_ event: TimelineFixtureEvent) -> TimelineRow {
            let row = event.row
            events[row.uniqueId] = event
            return row
        }

        private func record(_ change: TimelineDisplayChange, rows: [TimelineRow]) {
            pending.append(TimelineRowChange(change: change, rows: rows))
            generation += 1
        }
    }
#endif
