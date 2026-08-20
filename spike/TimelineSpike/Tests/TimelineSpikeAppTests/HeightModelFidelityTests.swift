import AppKit
import Foundation
import Testing
import TimelineSpikeCore
@testable import TimelineSpikeApp

/// Checks `SpikeRowHeightModel` against SwiftUI's own layout of the same row.
///
/// The model exists because measuring 10k rows through `NSHostingView` before the first frame
/// is not affordable. That trade is only honest if the modelled height is right, and "right"
/// has a direction: too tall leaves a sliver of empty space, too short clips the last line of
/// a message. This suite pins both.
@MainActor
@Suite("Height model fidelity", .serialized)
struct HeightModelFidelityTests {
    private func corpus(_ count: Int) -> [TimelineItem] {
        let generator = SyntheticEventGenerator(seed: HarnessConfiguration.default.seed)
        return generator.events(in: 0 ..< count).map { TimelineItem(event: $0) }
    }

    @Test("The model never comes out short, and never wastes more than a couple of points")
    func modelMatchesSwiftUI() {
        _ = NSApplication.shared
        let auditor = RowHeightAuditor()
        let model = SpikeRowHeightModel(measurer: CoreTextSpikeMeasurer())
        let rowWidth: CGFloat = 1080

        var worstShortfall: CGFloat = 0
        var worstSlack: CGFloat = 0
        var totalSlack: CGFloat = 0
        var measured = 0

        for item in corpus(250) {
            let laidOut = auditor.swiftUIHeight(for: item, rowWidth: rowWidth)
            guard laidOut > 0 else { continue }
            let modelled = model.height(for: item, rowWidth: rowWidth)
            let difference = modelled - laidOut
            measured += 1
            totalSlack += difference
            worstSlack = max(worstSlack, difference)
            worstShortfall = min(worstShortfall, difference)
        }

        print(
            "[S-14] height model over \(measured) rows: worst shortfall "
                + String(format: "%.2f", worstShortfall)
                + " pt, worst slack " + String(format: "%.2f", worstSlack)
                + " pt, mean " + String(format: "%.2f", totalSlack / CGFloat(max(1, measured))) + " pt"
        )

        #expect(measured > 200)
        // Clipping is the failure that matters.
        #expect(worstShortfall >= -0.01)
        // Slack is tolerable, but a large one would mean the two candidates fit different
        // numbers of rows on a screen and the frame times stop being comparable.
        #expect(worstSlack <= 1)
    }

    @Test("Rows with reactions and edits are modelled as accurately as plain ones")
    func decoratedRowsMatchSwiftUI() {
        _ = NSApplication.shared
        let auditor = RowHeightAuditor()
        let model = SpikeRowHeightModel(measurer: CoreTextSpikeMeasurer())
        let rowWidth: CGFloat = 720

        var worstShortfall: CGFloat = 0
        var worstSlack: CGFloat = 0
        for var item in corpus(120) {
            item.event.reactions = [Reaction(key: "👍", count: 3), Reaction(key: "🎉", count: 12)]
            item.event.editCount = 2
            item.daySeparator = item.event.timestamp

            let laidOut = auditor.swiftUIHeight(for: item, rowWidth: rowWidth)
            guard laidOut > 0 else { continue }
            let difference = model.height(for: item, rowWidth: rowWidth) - laidOut
            worstSlack = max(worstSlack, difference)
            worstShortfall = min(worstShortfall, difference)
        }

        print(
            "[S-14] decorated rows: worst shortfall " + String(format: "%.2f", worstShortfall)
                + " pt, worst slack " + String(format: "%.2f", worstSlack) + " pt"
        )
        #expect(worstShortfall >= -0.01)
        #expect(worstSlack <= 1)
    }
}
