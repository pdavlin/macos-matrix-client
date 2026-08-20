import SwiftUI
import TimelineSpikeCore

/// A deliberately naive renderer that proves the harness wiring works end to end.
///
/// **This is not candidate A.** It has no anchoring strategy, no height estimation, no
/// identity tuning and no scroll position management. Its numbers are a floor, not a
/// result, and they must never appear in the S-15 comparison.
///
/// What it is good for is showing S-13 and S-14 exactly what a renderer owes the probe:
///
/// - `reportVisible(_:range:)` from `onAppear`/`onDisappear` on each row.
/// - `reportOffset(_:for:)` from the row's `minY` in the viewport coordinate space.
/// - `viewportDidScroll(distanceFromTop:)` from the content offset.
struct PlaceholderRenderer: TimelineRenderer {
    nonisolated static let rendererID = "placeholder"
    nonisolated static let displayName = "Placeholder (not a candidate)"
    nonisolated static let summary =
        "Plain ScrollView + LazyVStack. Wiring demo only; do not compare."

    private let harness: SpikeHarness
    @State private var visible = VisibleSetTracker()

    init(harness: SpikeHarness) {
        self.harness = harness
    }

    var body: some View {
        GeometryReader { outer in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(harness.store.items) { item in
                        SpikeRowView(item: item, contentWidth: outer.size.width)
                            .onAppear {
                                visible.insert(item.id, store: harness.store)
                                publishVisible()
                            }
                            .onDisappear {
                                visible.remove(item.id, store: harness.store)
                                publishVisible()
                            }
                            .onGeometryChange(for: CGFloat.self) { proxy in
                                proxy.frame(in: .named(SpikeCoordinateSpace.viewport)).minY
                            } action: { minY in
                                harness.probe.reportOffset(Double(minY), for: item.id)
                            }
                    }
                }
                .background {
                    // Content offset probe: the top of the content relative to the
                    // viewport. Negative once scrolled, so the distance from the top of the
                    // loaded content is its magnitude.
                    GeometryReader { inner in
                        let minY = inner.frame(in: .named(SpikeCoordinateSpace.viewport)).minY
                        Color.clear
                            .onChange(of: minY, initial: true) { _, newValue in
                                harness.viewportDidScroll(distanceFromTop: Double(-newValue))
                            }
                    }
                }
            }
            .coordinateSpace(.named(SpikeCoordinateSpace.viewport))
            .defaultScrollAnchor(.bottom)
        }
    }

    private func publishVisible() {
        harness.probe.reportVisible(visible.ordered, range: visible.range)
    }
}

/// Tracks which rows are on screen.
///
/// `onAppear`/`onDisappear` arrive out of order, so the set is kept unordered and sorted on
/// read. The sort is over the visible rows only, a few dozen items, and it runs when the
/// visible set changes rather than per frame.
@Observable
@MainActor
final class VisibleSetTracker {
    private var ids: Set<EventID> = []
    private(set) var ordered: [EventID] = []
    private(set) var range: Range<Int>?

    func insert(_ id: EventID, store: TimelineStore) {
        ids.insert(id)
        recompute(store: store)
    }

    func remove(_ id: EventID, store: TimelineStore) {
        ids.remove(id)
        recompute(store: store)
    }

    private func recompute(store: TimelineStore) {
        ordered = ids.sorted()
        guard let lowest = ordered.first, let highest = ordered.last,
              let lowerIndex = store.itemIndex(for: lowest),
              let upperIndex = store.itemIndex(for: highest)
        else {
            range = nil
            return
        }
        range = lowerIndex ..< (upperIndex + 1)
    }
}
