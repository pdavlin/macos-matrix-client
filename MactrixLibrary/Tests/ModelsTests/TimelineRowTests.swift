import Foundation
@testable import Models
import Testing

/// S-31: the `TimelineRow` view-model surface — case construction and the
/// identity/reuse data the row layer keys off. The SDK mapping itself is
/// exercised in `MactrixIntegrationTests/TimelineRowMappingTests.swift`.
struct TimelineRowTests {
    @Test
    func messageRowCarriesUniqueIdAndEvent() {
        let row = TimelineRow.message(uniqueId: "u1", event: MockEventTimelineItem())

        #expect(row.uniqueId == "u1")
        #expect(row.reuseId == "message")

        guard case let .message(uniqueId, event) = row else {
            Issue.record("expected message row, got \(row)")
            return
        }
        #expect(uniqueId == "u1")
        #expect(event is MockEventTimelineItem)
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
        #expect(row.reuseId == "virtual")

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

        #expect(readMarker.reuseId == "virtual")
        #expect(timelineStart.reuseId == "virtual")
        #expect(readMarker.uniqueId == "r")
        #expect(timelineStart.uniqueId == "s")
    }
}
