#if os(macOS)
    import AppKit
#endif
@testable import Core
import Foundation
import MatrixRustSDK
import Models
import SwiftUI
import Testing
import UI

/// MATRIX-230: a reply row is measured while its quote is a placeholder, and
/// its height must follow the quote when the replied-to event loads: through
/// a row update when the SDK loads it, and through `LoadedReplyQuote` when
/// `LiveTimeline` loads it.
@MainActor
@Suite("Reply quote height", .serialized)
struct ReplyQuoteHeightTests {
    /// Narrow enough that the placeholder's message takes two lines.
    private static let width: CGFloat = 240
    private static let quotedEventId = "$quoted"
    private static let replyBody = "The reply text"

    init() {
        #if os(macOS)
            _ = NSApplication.shared
        #endif
    }

    @Test("A row update that loads the quote gives the row the loaded quote's height")
    func rowUpdateWithTheLoadedQuoteRemeasures() {
        let measurer = OffscreenRowMeasurer()
        var cache = TimelineRowHeightCache<Int>()
        var revision = 0

        let placeholderRow = Self.replyRow(quoting: .pending)
        let loadedRow = Self.replyRow(quoting: Self.loadedDetails)

        let placeholderHeight = cache.height(for: placeholderRow, width: Self.width, tokens: 0, revision: revision) { row, width in
            Self.measure(row, width: width, with: measurer)
        }
        // The container's update path (MATRIX-63): a new revision only when
        // the fingerprint says the height can have changed.
        if !TimelineRowHeightFingerprint.heightIsUnchanged(from: placeholderRow, to: loadedRow) {
            revision += 1
        }
        let loadedHeight = cache.height(for: loadedRow, width: Self.width, tokens: 0, revision: revision) { row, width in
            Self.measure(row, width: width, with: measurer)
        }

        let expected = Self.measure(loadedRow, width: Self.width, with: measurer)
        #expect(expected < placeholderHeight)
        #expect(loadedHeight == expected)
    }

    @Test("A quote the timeline loads gives the row the loaded quote's height")
    func timelineLoadRemeasures() {
        let measurer = OffscreenRowMeasurer()
        var cache = TimelineRowHeightCache<Int>()
        var revisions: [String: Int] = [:]
        // The SDK keeps the quote unavailable: the timeline loads it itself,
        // and no row update follows.
        var rows = [Self.replyRow(quoting: .unavailable), Self.plainRow()]
        var loaded: [String: MatrixRustSDK.EmbeddedEventDetails] = [:]

        func height(of index: Int) -> CGFloat {
            let row = rows[index]
            return cache.height(for: row, width: Self.width, tokens: 0, revision: revisions[row.uniqueId] ?? 0) { row, width in
                Self.measure(row, width: width, with: measurer, loaded: loaded)
            }
        }

        let placeholderHeight = height(of: 0)
        let plainHeight = height(of: 1)

        // What the container does when `LiveTimeline` posts the load.
        loaded[Self.quotedEventId] = Self.loadedDetails
        let changed = LoadedReplyQuote.apply(Self.loadedDetails.replyQuote, quoting: Self.quotedEventId, to: &rows) { _ in true }
        for index in changed {
            revisions[rows[index].uniqueId, default: 0] += 1
        }

        #expect(changed == IndexSet(integer: 0))
        #expect(rows[0].heightFingerprint?.replyQuote == Self.loadedDetails.replyQuote)
        let expected = Self.measure(rows[0], width: Self.width, with: measurer, loaded: loaded)
        #expect(expected < placeholderHeight)
        #expect(height(of: 0) == expected)
        #expect(height(of: 1) == plainHeight)
    }

    @Test("A second load of the same quote measures nothing")
    func secondLoadOfTheSameQuoteIsHeightNeutral() {
        var rows = [Self.replyRow(quoting: .pending)]
        let quote = Self.loadedDetails.replyQuote

        #expect(LoadedReplyQuote.apply(quote, quoting: Self.quotedEventId, to: &rows) { _ in true } == IndexSet(integer: 0))
        #expect(LoadedReplyQuote.apply(quote, quoting: Self.quotedEventId, to: &rows) { _ in true }.isEmpty)
    }

    @Test("A load leaves the rows that quote another event, and the rows of another timeline")
    func loadTouchesOnlyTheRowsThatQuoteTheEvent() {
        var rows = [Self.replyRow(quoting: .pending, quotedEventId: "$other"), Self.replyRow(quoting: .pending)]
        let quote = Self.loadedDetails.replyQuote

        #expect(LoadedReplyQuote.apply(quote, quoting: Self.quotedEventId, to: &rows) { _ in false }.isEmpty)
        #expect(LoadedReplyQuote.apply(quote, quoting: Self.quotedEventId, to: &rows) { _ in true } == IndexSet(integer: 1))
        #expect(rows[0].heightFingerprint?.replyQuote == .placeholder)
    }

    @Test("The quote follows the SDK's reply details")
    func quoteFollowsTheDetails() {
        let cases: [(MatrixRustSDK.EmbeddedEventDetails, ReplyQuoteGeometry)] = [
            (.unavailable, .placeholder),
            (.pending, .placeholder),
            (.error(message: "not found"), .failed(message: "not found")),
            (Self.loadedDetails, .quote(sender: "Bob", text: "ok")),
        ]
        for (details, quote) in cases {
            let row = Self.replyRow(quoting: details)
            #expect(details.replyQuote == quote)
            #expect(row.heightFingerprint?.replyQuote == quote)
            #expect(row.quotedEventId == Self.quotedEventId)
        }
        #expect(Self.plainRow().heightFingerprint?.replyQuote == nil)
        #expect(Self.plainRow().quotedEventId == nil)
    }

    @Test("A sender without a display name is quoted by user ID")
    func senderWithoutDisplayNameIsQuotedByUserId() {
        let details = MatrixRustSDK.EmbeddedEventDetails.ready(
            content: Self.textContent("ok"),
            sender: "@bob:example.org",
            senderProfile: .unavailable,
            timestamp: 1_700_000_000_000,
            eventOrTransactionId: .eventId(eventId: Self.quotedEventId)
        )
        #expect(details.replyQuote == .quote(sender: "@bob:example.org", text: "ok"))
    }

    // MARK: - Fixtures

    private static let loadedDetails = MatrixRustSDK.EmbeddedEventDetails.ready(
        content: textContent("ok"),
        sender: "@bob:example.org",
        senderProfile: .ready(displayName: "Bob", displayNameAmbiguous: false, avatarUrl: nil, status: nil, call: nil),
        timestamp: 1_700_000_000_000,
        eventOrTransactionId: .eventId(eventId: quotedEventId)
    )

    private static func textContent(
        _ body: String,
        inReplyTo: MatrixRustSDK.InReplyToDetails? = nil
    ) -> MatrixRustSDK.TimelineItemContent {
        .msgLike(content: MatrixRustSDK.MsgLikeContent(
            kind: .message(content: MatrixRustSDK.MessageContent(
                msgType: .text(content: MatrixRustSDK.TextMessageContent(body: body, formatted: nil)),
                body: body,
                isEdited: false,
                mentions: nil
            )),
            inReplyTo: inReplyTo,
            threadRoot: nil,
            threadSummary: nil
        ))
    }

    private static func replyRow(
        quoting details: MatrixRustSDK.EmbeddedEventDetails,
        quotedEventId: String = quotedEventId
    ) -> Models.TimelineRow {
        let inReplyTo = FakeInReplyTo(eventId: quotedEventId, details: details)
        return row(uniqueId: "reply.\(quotedEventId)", content: textContent(replyBody, inReplyTo: inReplyTo))
    }

    private static func plainRow() -> Models.TimelineRow {
        row(uniqueId: "plain", content: textContent(replyBody))
    }

    private static func row(uniqueId: String, content: MatrixRustSDK.TimelineItemContent) -> Models.TimelineRow {
        let event = MatrixRustSDK.EventTimelineItem(
            isRemote: true,
            eventOrTransactionId: .eventId(eventId: "$\(uniqueId)"),
            sender: "@alice:example.org",
            senderProfile: .unavailable,
            forwarder: nil,
            forwarderProfile: nil,
            isOwn: false,
            isEditable: false,
            content: content,
            reactions: [],
            eventTypeRaw: nil,
            timestamp: 1_700_000_000_000,
            localSendState: nil,
            editSendState: nil,
            redactionSendState: nil,
            redactionReason: nil,
            localCreatedAt: nil,
            readReceipts: [:],
            origin: nil,
            canBeRepliedTo: true,
            lazyProvider: MatrixRustSDK.LazyTimelineItemProvider(noHandle: .init())
        )
        return MatrixRustSDK.TimelineItem.row(for: event, uniqueId: uniqueId)
    }

    /// The quote and the body as `ChatMessageView` stacks them, with the quote
    /// the row resolves to: the details the timeline loaded, else the SDK's.
    private static func measure(
        _ row: Models.TimelineRow,
        width: CGFloat,
        with measurer: OffscreenRowMeasurer,
        loaded: [String: MatrixRustSDK.EmbeddedEventDetails] = [:]
    ) -> CGFloat {
        guard case let .message(_, event, _, _) = row,
              let event = event as? MatrixRustSDK.EventTimelineItem,
              case let .msgLike(content) = event.content
        else {
            Issue.record("the row is a message")
            return 0
        }
        let quote = content.inReplyTo.map { loaded[$0.eventId()] ?? $0.event() }?.replyQuote
        let view = VStack(alignment: .leading, spacing: 10) {
            if let quote {
                UI.ReplyQuoteView(quote: quote)
            }
            Text(verbatim: replyBody).fixedSize(horizontal: false, vertical: true)
        }
        return measurer.size(of: view, in: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)).height
    }
}

/// An SDK reply relation whose replied-to event is given, so the mapping can
/// be tested without a Rust handle. The SDK exposes `init(noHandle:)` for
/// fakes.
private final class FakeInReplyTo: MatrixRustSDK.InReplyToDetails, @unchecked Sendable {
    private let quotedEventId: String
    private let details: MatrixRustSDK.EmbeddedEventDetails

    init(eventId: String, details: MatrixRustSDK.EmbeddedEventDetails) {
        quotedEventId = eventId
        self.details = details
        super.init(noHandle: MatrixRustSDK.InReplyToDetails.NoHandle())
    }

    @available(*, unavailable)
    required init(unsafeFromHandle _: UInt64) {
        fatalError("FakeInReplyTo must be created with init(eventId:details:)")
    }

    override func event() -> MatrixRustSDK.EmbeddedEventDetails {
        details
    }

    override func eventId() -> String {
        quotedEventId
    }
}
