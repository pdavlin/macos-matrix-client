import Models
import SwiftUI
import UIKit

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
    /// The container and composer on a scripted feed: sender runs, day
    /// dividers, a read marker, back-pagination, and a stream of arrivals,
    /// reaction re-tallies, and edits that exercise the drain and the anchor.
    /// The newest rows show the MATRIX-86 surfaces: a failed send, an HTML
    /// body, a reply, and an image. `-TimelineFixtureReply` opens the
    /// composer's reply preview at launch.
    struct TimelineFixtureScreen: View {
        @State private var feed = TimelineFixtureFeed(
            opensReply: ProcessInfo.processInfo.arguments.contains("-TimelineFixtureReply")
        )

        var body: some View {
            NavigationStack {
                ConversationLayout {
                    TimelineContainer(
                        feed: feed,
                        timeline: nil,
                        imageLoader: nil,
                        ownUserId: TimelineFixtureFeed.ownUserId,
                        showsReadReceipts: false,
                        media: TimelineFixtureMediaLoader(),
                        fallbackActions: feed
                    )
                } composer: {
                    ComposerBar(target: feed, placeholder: "Message fixture")
                }
                .navigationTitle("Timeline fixture")
                .navigationBarTitleDisplayMode(.inline)
            }
            .task { await feed.run() }
        }
    }

    /// A fake event with its own body, reaction pills, and the optional
    /// MATRIX-86 content: an HTML body, media, a quoted reply, a failed send.
    struct TimelineFixtureEvent: TimelineTextEvent {
        let sender: String
        let name: String
        let date: Date
        let body: String
        let reactionPills: [TimelineReactionPill]
        var formattedBody: String?
        var media: TimelineMedia?
        var quotedReply: ComposerReply?
        var sendFailure: String?

        var isRemote: Bool { sendFailure == nil }
        var senderProfileDetails: ProfileDetails {
            .ready(displayName: name, displayNameAmbiguous: false, avatarUrl: nil)
        }

        var isOwn: Bool { sender == TimelineFixtureFeed.ownUserId }
        var isEditable: Bool { false }
        var sendState: LocalSendState? {
            sendFailure.map { .sendingFailed(message: $0, isRecoverable: true) }
        }

        var localCreatedAt: UInt64? { nil }
        var userReadReceipts: [String: Receipt] { [:] }
        var canBeRepliedTo: Bool { sendFailure == nil }
        var userId: String { sender }
        var displayName: String? { name }
        var avatarUrl: String? { nil }

        /// True for a row that shows a MATRIX-86 surface. The scripted
        /// stream leaves these alone, so a screenshot finds them as built.
        var isShowcase: Bool {
            formattedBody != nil || media != nil || quotedReply != nil || sendFailure != nil
        }

        var row: TimelineRow {
            .message(
                uniqueId: "fixture.\(date.timeIntervalSince1970)",
                event: self,
                kind: media == nil ? .text : .media,
                heightFingerprint: TimelineRowHeightFingerprint(
                    body: MessageBodyGeometry(
                        variant: media == nil ? "text" : "image",
                        text: media == nil ? body : "",
                        formattedText: formattedBody,
                        mediaWidth: media?.width,
                        mediaHeight: media?.height,
                        secondaryText: media?.caption
                    ),
                    hasReplyPreview: quotedReply != nil,
                    sendFailureMessage: sendFailure,
                    senderName: name,
                    reactions: ReactionStripGeometry(
                        reactions: reactionPills.lazy.map { (key: $0.key, senderCount: $0.senders.count) },
                        hasReadReceipts: false
                    )
                )
            )
        }

        func with(body: String? = nil, reactionPills: [TimelineReactionPill]? = nil) -> TimelineFixtureEvent {
            var copy = TimelineFixtureEvent(
                sender: sender,
                name: name,
                date: date,
                body: body ?? self.body,
                reactionPills: reactionPills ?? self.reactionPills
            )
            copy.formattedBody = formattedBody
            copy.media = media
            copy.quotedReply = quotedReply
            copy.sendFailure = sendFailure
            return copy
        }
    }

    /// Fixture media: a generated image, so the image row needs no account.
    @MainActor
    struct TimelineFixtureMediaLoader: TimelineMediaLoading {
        static let image = TimelineMedia(
            kind: .image,
            filename: "fixture-sunset.png",
            caption: "The view from the office",
            mimeType: "image/png",
            byteSize: 48000,
            duration: nil,
            width: 400,
            height: 240,
            source: nil,
            previewSource: nil,
            previewKey: "fixture://sunset"
        )

        func previewData(for _: TimelineMedia) async throws -> Data {
            try await Task.sleep(for: .milliseconds(300))
            return Self.pngData()
        }

        func download(_ media: TimelineMedia) async throws -> MediaViewerItem {
            let url = FileManager.default.temporaryDirectory.appending(path: media.filename)
            try Self.pngData().write(to: url)
            return MediaViewerItem(url: url, kind: media.kind, title: media.filename, fileHandle: nil)
        }

        /// A 400 by 240 sky, sun, and sea.
        private static func pngData() -> Data {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 240), format: format)
            return renderer.pngData { context in
                UIColor.systemOrange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 400, height: 170))
                UIColor.systemYellow.setFill()
                context.cgContext.fillEllipse(in: CGRect(x: 160, y: 90, width: 80, height: 80))
                UIColor.systemTeal.setFill()
                context.fill(CGRect(x: 0, y: 170, width: 400, height: 70))
            }
        }
    }

    @MainActor @Observable
    final class TimelineFixtureFeed: TimelineFeed {
        nonisolated static let ownUserId = "@me:fixture"
        private static let senders: [(id: String, name: String)] = [
            ("@ada:fixture", "Ada Lovelace"),
            ("@bob:fixture", "Bob Kahn"),
            (ownUserId, "Me"),
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

        /// The composer's reply target.
        private(set) var reply: ComposerReply?

        init(opensReply: Bool = false) {
            items = (0 ..< 30).map { _ in olderRow() }
            items.insert(.virtual(uniqueId: "fixture.readMarker", item: .readMarker), at: 6)
            items.insert(contentsOf: showcaseRows(), at: 0)
            if opensReply, let target = events.values.first(where: { $0.formattedBody != nil }) {
                reply = Self.reply(to: target)
            }
        }

        /// The MATRIX-86 surfaces, newest first: a failed send, an HTML body,
        /// a reply, and an image.
        private func showcaseRows() -> [TimelineRow] {
            let base = Date.now
            var image = TimelineFixtureEvent(
                sender: "@bob:fixture",
                name: "Bob Kahn",
                date: base - 40,
                body: "fixture-sunset.png",
                reactionPills: []
            )
            image.media = TimelineFixtureMediaLoader.image
            var reply = TimelineFixtureEvent(
                sender: "@ada:fixture",
                name: "Ada Lovelace",
                date: base - 30,
                body: "Looks great, ship it.",
                reactionPills: []
            )
            reply.quotedReply = ComposerReply(id: "fixture.image", senderName: "Bob Kahn", preview: "The view from the office")
            var html = TimelineFixtureEvent(
                sender: "@bob:fixture",
                name: "Bob Kahn",
                date: base - 20,
                body: "Release notes: italic, inline code, and a link.",
                reactionPills: []
            )
            html.formattedBody = "<p><strong>Release notes</strong>: <em>italic</em>, <code>inline code</code>, "
                + "and <a href=\"https://matrix.org\">a link</a>.</p><ul><li>First item</li><li>Second item</li></ul>"
            var failed = TimelineFixtureEvent(
                sender: Self.ownUserId,
                name: "Me",
                date: base - 10,
                body: "This one did not make it.",
                reactionPills: []
            )
            failed.sendFailure = "the server is unreachable"
            return [failed, html, reply, image].map { remember($0) }
        }

        private static func reply(to event: TimelineFixtureEvent) -> ComposerReply {
            ComposerReply(id: "fixture.\(event.date.timeIntervalSince1970)", senderName: event.name, preview: event.body)
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
            guard items.indices.contains(index), let event = events[items[index].uniqueId], !event.isShowcase else { return nil }
            return event
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

        private func index(ofRow rowId: String) -> Int? {
            items.firstIndex { $0.uniqueId == rowId }
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

    extension TimelineFixtureFeed: ComposerTarget {
        func cancelReply() {
            reply = nil
        }

        /// Appends the message as the newest row, quoting the reply target.
        func send(body: String) async throws {
            var event = TimelineFixtureEvent(sender: Self.ownUserId, name: "Me", date: .now, body: body, reactionPills: [])
            event.quotedReply = reply
            let row = remember(event)
            items.insert(row, at: 0)
            record(.insert(index: 0, count: 1), rows: [row])
            requestScrollToBottom()
        }

        func noteTyping() async {}
    }

    extension TimelineFixtureFeed: TimelineFallbackRowActions {
        func reply(toRow rowId: String) {
            guard let event = events[rowId] else { return }
            reply = Self.reply(to: event)
        }

        /// The fixture's send succeeds on retry: the failure clears.
        func retrySend(ofRow rowId: String) {
            guard let index = index(ofRow: rowId), var event = events[rowId] else { return }
            event.sendFailure = nil
            let row = remember(event)
            items[index] = row
            record(.update(index: index), rows: [row])
        }

        func discardSend(ofRow rowId: String) {
            guard let index = index(ofRow: rowId) else { return }
            items.remove(at: index)
            events[rowId] = nil
            record(.remove(index: index, count: 1), rows: [])
        }
    }
#endif
