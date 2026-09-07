import Foundation
@testable import Models
import Testing

/// S-31: the `TimelineRow` view-model surface — case construction and the
/// identity/reuse data the row layer keys off. The SDK mapping itself is
/// exercised in `MactrixIntegrationTests/TimelineRowMappingTests.swift`.
struct TimelineRowTests {
    @Test
    func messageRowCarriesUniqueIdAndEvent() {
        let row = TimelineRow.message(uniqueId: "u1", event: MockEventTimelineItem(), kind: .text, hasReactions: false)

        #expect(row.uniqueId == "u1")
        #expect(row.reuseId == "message.text")

        guard case let .message(uniqueId, event, kind, hasReactions) = row else {
            Issue.record("expected message row, got \(row)")
            return
        }
        #expect(uniqueId == "u1")
        #expect(event is MockEventTimelineItem)
        #expect(kind == .text)
        #expect(hasReactions == false)
    }

    @Test
    func stateRowCarriesUniqueIdEventAndName() {
        let row = TimelineRow.state(uniqueId: "u2", event: MockEventTimelineItem(), name: "joined room")

        #expect(row.uniqueId == "u2")
        #expect(row.reuseId == "state")

        guard case let .state(uniqueId, event, name) = row else {
            Issue.record("expected state row, got \(row)")
            return
        }
        #expect(uniqueId == "u2")
        #expect(event is MockEventTimelineItem)
        #expect(name == "joined room")
    }

    @Test
    func virtualRowCarriesUniqueIdAndItem() {
        let row = TimelineRow.virtual(uniqueId: "u3", item: .dateDivider(date: Date(timeIntervalSince1970: 0)))

        #expect(row.uniqueId == "u3")
        #expect(row.reuseId == "virtual.dateDivider")

        guard case let .virtual(uniqueId, .dateDivider(date)) = row else {
            Issue.record("expected virtual dateDivider row, got \(row)")
            return
        }
        #expect(uniqueId == "u3")
        #expect(date.timeIntervalSince1970 == 0.0)
    }

    @Test
    func virtualRowSupportsAllVirtualItemKinds() {
        let readMarker = TimelineRow.virtual(uniqueId: "r", item: .readMarker)
        let timelineStart = TimelineRow.virtual(uniqueId: "s", item: .timelineStart)

        #expect(readMarker.reuseId == "virtual.readMarker")
        #expect(timelineStart.reuseId == "virtual.timelineStart")
        #expect(readMarker.uniqueId == "r")
        #expect(timelineStart.uniqueId == "s")
    }

    /// S-34: recycling pools are split by render shape. A recycled
    /// `NSHostingView` only reuses its subview tree when the incoming row has
    /// the same shape, so a text row and an image row must not share an
    /// identifier.
    @Test
    func messageReuseIdSeparatesKindsAndReactionStrips() {
        var identifiers: Set<String> = []
        for kind in MessageRowKind.allCases {
            for hasReactions in [false, true] {
                let row = TimelineRow.message(
                    uniqueId: "u", event: MockEventTimelineItem(), kind: kind, hasReactions: hasReactions
                )
                identifiers.insert(row.reuseId)
            }
        }

        #expect(identifiers.count == MessageRowKind.allCases.count * 2)
        #expect(identifiers.contains("message.media.reactions"))
        #expect(identifiers.contains("message.attachment"))
    }

    @Test
    func decorationRowsAreDistinctFromItemRows() {
        let typing = TimelineRow.typingIndicator(uniqueId: "t", names: ["Ada"])
        let pagination = TimelineRow.paginationActivity(uniqueId: "p")
        let unsupported = TimelineRow.unsupported(uniqueId: "x")

        #expect(typing.isDecoration)
        #expect(pagination.isDecoration)
        #expect(!unsupported.isDecoration)

        #expect(typing.reuseId == "typingIndicator")
        #expect(pagination.reuseId == "paginationActivity")
        #expect(unsupported.reuseId == "unsupported")
        #expect(typing.uniqueId == "t")
    }
}
