import AppKit
import SwiftUI
import TimelineSpikeCore

/// `SpikeRowView` pinned to the top-left of whatever box the table gives it.
///
/// The row is authored as a `VStack` with an intrinsic height. Handed a taller box it would
/// centre itself, which would make every height error look like a layout bug, so the frame
/// modifier nails it to the top.
struct HostedSpikeRow: View {
    var item: TimelineItem?
    var rowWidth: CGFloat

    var body: some View {
        if let item {
            SpikeRowView(item: item, contentWidth: rowWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The row as the height model sees it: no expanding frame, so SwiftUI reports the height it
/// actually wants instead of taking everything on offer. Measurement only.
struct MeasuredSpikeRow: View {
    var item: TimelineItem?
    var rowWidth: CGFloat

    var body: some View {
        if let item {
            SpikeRowView(item: item, contentWidth: rowWidth)
        }
    }
}

/// The table cell: one `NSHostingView` per row, hosting the shared SwiftUI row.
///
/// ## Why SwiftUI inside an AppKit table
///
/// S-15 is a question about list architecture — who owns recycling, height bookkeeping and
/// scroll position — not about who draws a message bubble. Hosting `SpikeRowView` keeps the
/// per-row drawing workload byte-identical to the SwiftUI candidate, so the frame times
/// differ only by the thing under test. An AppKit-purist row of `NSTextField`s would measure
/// faster and prove nothing.
///
/// ## What it costs
///
/// - Every row is its own SwiftUI graph. There is no shared render tree across rows, so
///   invalidation is per-row, and a full-window scroll builds and tears down a few dozen
///   hosts.
/// - Assigning `rootView` on a recycled host is a full SwiftUI update for that host, not a
///   cheap diff against a sibling row, because the previous root described a different event.
/// - AppKit sizes the cell; SwiftUI then lays the row out inside it. The row is measured
///   twice per appearance, once by `SpikeRowHeightModel` and once by SwiftUI.
///
/// A production build would keep the table and draw the row in AppKit, which removes all
/// three. Read the S-14 numbers as a floor for the AppKit approach, not its ceiling.
final class SpikeRowHostingView: NSHostingView<HostedSpikeRow> {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("spike.row.hosting")

    init() {
        super.init(rootView: HostedSpikeRow(item: nil, rowWidth: 0))
        identifier = Self.reuseIdentifier
        // The row height comes from the height model. Letting the host publish an intrinsic
        // size or install its own constraints would put SwiftUI and the table in a fight over
        // the cell's geometry, and the table has to win: it is the one that already told the
        // scroll view how tall the document is.
        sizingOptions = []
        translatesAutoresizingMaskIntoConstraints = true
        autoresizingMask = [.width, .height]
        // A row that overflows its measured height clips instead of painting over its
        // neighbour, so a height-model error shows up as a clipped last line rather than as
        // an overlap that is easy to miss.
        clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        preconditionFailure("SpikeRowHostingView is created in code, never from a nib")
    }

    required init(rootView: HostedSpikeRow) {
        super.init(rootView: rootView)
    }

    func configure(item: TimelineItem, rowWidth: CGFloat) {
        rootView = HostedSpikeRow(item: item, rowWidth: rowWidth)
    }
}

/// Optional cross-check on `SpikeRowHeightModel`, enabled with `TIMELINE_SPIKE_HEIGHT_AUDIT=1`.
///
/// It lays a row out through SwiftUI and reports the difference against the modelled height.
/// This is a debugging aid and it is off by default: it is a second full layout of every row
/// it looks at, which is exactly the cost the height model exists to avoid, so a run with the
/// audit on is not a run worth recording.
@MainActor
final class RowHeightAuditor {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TIMELINE_SPIKE_HEIGHT_AUDIT"] == "1"
    }

    /// A controller rather than a bare hosting view: `sizeThatFits(in:)` proposes a width to
    /// SwiftUI and returns the height SwiftUI wants for it, which is the measurement the model
    /// is trying to predict. A hosting view's `fittingSize` answers a different question — the
    /// size the content would like if nothing constrained it — and reports text as if it never
    /// wrapped.
    private let controller = NSHostingController(rootView: MeasuredSpikeRow(item: nil, rowWidth: 0))
    private var worstDifference: CGFloat = 0
    private var auditedRows = 0
    private var reportedRows = 0

    init() {}

    /// The height SwiftUI itself gives the row at this width.
    func swiftUIHeight(for item: TimelineItem, rowWidth: CGFloat) -> CGFloat {
        controller.rootView = MeasuredSpikeRow(item: item, rowWidth: rowWidth)
        return controller.sizeThatFits(
            in: CGSize(width: rowWidth, height: .greatestFiniteMagnitude)
        ).height
    }

    func audit(item: TimelineItem, rowWidth: CGFloat, modelledHeight: CGFloat) {
        let laidOut = swiftUIHeight(for: item, rowWidth: rowWidth)
        guard laidOut > 0 else { return }

        auditedRows += 1
        let difference = modelledHeight - laidOut
        if abs(difference) > abs(worstDifference) {
            worstDifference = difference
        }
        // A negative difference means the model is short and the row is clipping, which is the
        // failure that matters, so it is reported every time. Positive slack is reported
        // sparsely; it only wastes space.
        guard difference < -0.5 || (difference > 0.5 && reportedRows < 20) else { return }
        reportedRows += 1
        print(
            "[AppKitTable] height audit: event \(item.event.id) modelled "
                + String(format: "%.2f", modelledHeight)
                + " SwiftUI " + String(format: "%.2f", laidOut)
                + " difference " + String(format: "%+.2f", difference)
                + " (worst so far " + String(format: "%+.2f", worstDifference)
                + " over \(auditedRows) rows)"
        )
    }
}
