import SwiftUI
import TimelineSpikeCore

/// Candidate A (S-13): the inverted timeline built out of stock SwiftUI scroll APIs.
///
/// This is the honest best case for "keep the timeline in SwiftUI". It uses no
/// `NSViewRepresentable`, no private API, and no post-hoc corrective scrolling. Everything
/// that holds the scroll position is declarative and runs inside SwiftUI's own layout pass,
/// so what the drift instrument reports and what a human sees agree. See "Rejected: fixing
/// it up afterwards" below for why that restriction matters more than it sounds.
///
/// # Anchoring
///
/// Four mechanisms, one job each. No two of them are the same technique wearing a
/// different hat, which is what makes the result readable: if a scenario fails, the
/// scenario says which mechanism failed.
///
/// ## 1. Start at the newest event
///
/// `defaultScrollAnchor(.bottom, for: .initialOffset)` places the first offset at the end
/// of the content. `ScrollPosition(idType:edge:)` is seeded with `.bottom` for the same
/// reason, so the two agree rather than race. Items stay in natural ascending order and
/// the *view* is inverted by anchoring, not by the `scaleEffect(y: -1)` flip trick: that
/// trick reverses hit-testing, accessibility order and text selection, and it turns the
/// interesting case (prepend) into the boring one (append) by hiding it, which would make
/// this candidate a strawman in its own favour.
///
/// ## 2. Absorb content-size changes above the viewport
///
/// `defaultScrollAnchor(.bottom, for: .sizeChanges)` is the load-bearing line, and it is
/// the one the placeholder renderer does not have. It says: when the content size changes,
/// keep the *bottom* edge of the content where it was relative to the viewport, and move
/// the offset to compensate.
///
/// In an inverted timeline nearly every size change happens above the viewport:
///
/// - A back-pagination prepend inserts 50 rows at index 0. Content height grows by the
///   height of those rows; the offset grows by the same amount; nothing visible moves.
///   This is exactly the 33.6 pt jump the placeholder produced once in twenty prepends.
/// - A `LazyVStack` has no height-estimation API. Rows that have never been realized
///   contribute nothing to the content height, so scrolling upward through unrealized
///   content changes the content size continuously, a few times per frame. Bottom
///   anchoring absorbs that churn too, for the same reason.
///
/// The known cost is stated plainly because it will show up in the numbers: a size change
/// *below* the viewport — a mutation that grows an off-screen event older than the visible
/// window — moves visible content by the same amount, because holding the bottom edge
/// still is the wrong answer for that case. SwiftUI's size-change anchor is an edge, not
/// an item, and an edge cannot be right in both directions at once. Mechanism 3 exists to
/// cover the other direction.
///
/// ## 3. Pin the topmost visible row across content changes
///
/// `scrollPosition(_:anchor: .top)` over a `scrollTargetLayout()`-marked `LazyVStack`.
/// SwiftUI writes the identity of the row currently at the top of the viewport into the
/// binding as the user scrolls, and holds that row at the anchor as the content changes.
/// Unlike mechanism 2 this is item-relative, so it is direction-agnostic: a change below
/// the anchored row cannot move it.
///
/// Mechanisms 2 and 3 agree in direction for every above-the-viewport change, so they
/// reinforce rather than fight; they differ only for below-the-viewport changes, where 3
/// is right and 2 is wrong. The two are kept together deliberately: if S4 (prepend) is
/// clean and S2 (mutation storm) drifts, the edge anchor is doing the work and the item
/// anchor is not, and that is a result for S-15 rather than a bug to paper over.
///
/// ## 4. Never scroll the timeline from application code
///
/// The renderer never calls `scrollTo`. It cannot: a correction can only be applied after
/// the offending layout has already been observed, which means at least one presented
/// frame of visible jump. The drift instrument settles three frames after a change
/// (`AnchorProbe.settleTicks`), so a corrective scroll would read as ~0 pt of drift while
/// the user watched the timeline flinch and snap back. That is the single easiest way to
/// produce a dishonest number in this harness. SCENARIOS.md §4 asks the operator to record
/// visible jumps by eye for exactly this reason; this candidate is built so the eye and
/// the instrument cannot disagree.
///
/// # Rejected: `List`
///
/// `List` was the other obvious shape. It was not chosen because `scrollTargetLayout()`
/// does not apply to its rows, so mechanism 3 and the `onScrollTargetVisibilityChange`
/// visible-set reporting below both become unavailable, and the probe would fall back to
/// the placeholder's out-of-order `onAppear`/`onDisappear` bookkeeping. On top of that,
/// `List` adds its own row insets, separators and selection chrome, and SCENARIOS.md §8
/// requires the rendered row to match `SpikeRowMetrics` exactly.
///
/// If this candidate fails on S4, a `List`-based variant is the obvious next probe before
/// S-15 concludes anything about SwiftUI in general: `List` on macOS is backed by
/// AppKit-grade row recycling and may anchor insertions natively.
struct SwiftUIListRenderer: TimelineRenderer {
    nonisolated static let rendererID = "swiftui-lazyvstack-anchored"
    nonisolated static let displayName = "SwiftUI (LazyVStack, anchored)"
    nonisolated static let summary =
        "ScrollView + LazyVStack. Bottom size-change anchor plus a ScrollPosition item anchor."

    private let harness: SpikeHarness

    /// The scroll position lives in a reference box rather than directly in `@State`.
    ///
    /// SwiftUI writes the anchored row's identity into this binding every time the topmost
    /// visible row changes, which during a scroll is several times a second. Holding that
    /// in `@State` would invalidate this view on every write, and this view's body
    /// re-evaluates `ForEach(harness.store.items)` over the whole loaded window. The
    /// instrument would then be measuring an invalidation storm that the renderer
    /// inflicted on itself.
    ///
    /// This is not the throttling that SCENARIOS.md §8 forbids: no store read is skipped,
    /// delayed or coalesced. The store is `@Observable` and still invalidates this view on
    /// every mutation. Only SwiftUI's own scroll-position bookkeeping is kept off the
    /// invalidation path.
    @State private var anchor = ScrollAnchorBox()

    init(harness: SpikeHarness) {
        self.harness = harness
    }

    var body: some View {
        GeometryReader { outer in
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Identity is `TimelineItem.id`, an `EventID` wrapping an `Int`: stable
                    // across prepends (an event's index on the generator line never
                    // changes), unique, independent of array position, and constant-time to
                    // hash. A prepend therefore reads to `ForEach` as fifty insertions at
                    // the front, not as a wholesale replacement.
                    ForEach(harness.store.items) { item in
                        AnchoredRow(
                            item: item,
                            contentWidth: outer.size.width,
                            probe: harness.probe
                        )
                        .equatable()
                    }
                }
                // Marks the stack's children as scroll targets, which is what
                // `scrollPosition(_:anchor:)` and `onScrollTargetVisibilityChange` resolve
                // identities against. No `scrollTargetBehavior` is set, so nothing snaps.
                .scrollTargetLayout()
            }
            .coordinateSpace(.named(SpikeCoordinateSpace.viewport))
            // Mechanism 1: first offset at the newest event.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // Content shorter than the viewport sits at the bottom, chat-style, rather
            // than floating at the top. Not measured by any scenario; correct anyway.
            .defaultScrollAnchor(.bottom, for: .alignment)
            // Mechanism 2: the prepend anchor. See the type documentation.
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            // Mechanism 3: the item anchor.
            .scrollPosition(anchor.binding, anchor: .top)
            .onScrollTargetVisibilityChange(
                idType: EventID.self,
                // Well below the 0.5 default: the probe wants "on screen at all", and so
                // does the mutation driver. At 0.5 a row half off the top edge counts as
                // off-screen, and mutating it as an "off-screen" target would move visible
                // content and score as anchoring drift that never happened.
                //
                // Not 0. A `LazyVStack` realizes rows beyond the viewport, and a threshold
                // that admits a zero-area intersection risks reporting the realization
                // buffer as visible. The probe tracks the middle of whatever it is told is
                // visible, so that would aim the whole drift measurement at a row nobody
                // can see. 0.05 is unambiguously "part of this row is on screen".
                threshold: 0.05
            ) { ids in
                publishVisible(ids)
            }
            .onScrollGeometryChange(for: Double.self) { geometry in
                // `AnchorProbe`'s contract for `viewportDidScroll` is the distance from the
                // top of the loaded content. That is the content offset, adjusted for the
                // top inset so the value is zero when the first row is flush with the top
                // of the viewport. Reading it from `ScrollGeometry` instead of a
                // `GeometryReader` in the content background means one callback per changed
                // offset rather than a geometry proxy resolved on every layout pass.
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, distanceFromTop in
                harness.viewportDidScroll(distanceFromTop: distanceFromTop)
            }
        }
    }

    /// Hands the probe the on-screen set, topmost first, with its item-index range.
    ///
    /// `onScrollTargetVisibilityChange` does not document an order for the identifiers it
    /// reports, and `AnchorProbe.reportVisible(_:range:)` requires top of the viewport
    /// first. Sorting is safe and cheap here for a reason specific to this store:
    /// `EventID` orders by position on the generator index line, `TimelineStore` guarantees
    /// `items` is contiguous and ascending on that line, and the visible set is a few dozen
    /// rows.
    private func publishVisible(_ ids: [EventID]) {
        let ordered = ids.sorted()
        harness.probe.reportVisible(
            ordered,
            range: harness.store.visibleRange(spanning: ordered)
        )
    }
}

/// One row, plus the geometry reporting the probe needs.
///
/// `Equatable` is deliberate. Every mutation replaces `TimelineStore.items`, which
/// invalidates the timeline view, which re-runs the body of every realized row even though
/// a storm tick touches six of them. Comparing the row's inputs skips the bodies whose
/// content did not change — the equivalent of AppKit reloading one row instead of the
/// table. It changes how often the shared workload runs, never what the workload is:
/// `SpikeRowView` and `SpikeRowMetrics` are used exactly as given, per SCENARIOS.md §8.
///
/// The row is unary: its body is a single modified `SpikeRowView`, and `SpikeRowView`'s own
/// body is a single `VStack`. That keeps row identity templatable from the `ForEach`
/// element id.
private struct AnchoredRow: View, Equatable {
    let item: TimelineItem
    let contentWidth: CGFloat
    /// Invariant for the lifetime of the renderer, so it takes no part in `==`.
    let probe: AnchorProbe

    var body: some View {
        SpikeRowView(item: item, contentWidth: contentWidth)
            // `minY` in the viewport's coordinate space is points from the top edge of the
            // viewport, increasing downward, with the scroll position already folded in —
            // which is `AnchorProbe.reportOffset`'s contract exactly.
            //
            // Every row reports, not just the tracked one. The probe drops offsets for
            // untracked identifiers, and reporting from every row means the tracked row's
            // post-change position is always on record before the settle window closes,
            // whichever row the probe happens to be tracking.
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(SpikeCoordinateSpace.viewport)).minY
            } action: { minY in
                probe.reportOffset(Double(minY), for: item.id)
            }
    }

    nonisolated static func == (lhs: AnchoredRow, rhs: AnchoredRow) -> Bool {
        lhs.item == rhs.item && lhs.contentWidth == rhs.contentWidth
    }
}

/// Reference storage for the scroll position, so SwiftUI's write-back does not invalidate
/// the timeline. See `SwiftUIListRenderer.anchor`.
@MainActor
private final class ScrollAnchorBox {
    /// Seeded to the bottom edge so the first layout lands on the newest event even before
    /// SwiftUI has an anchored row identity to hold onto.
    private var position = ScrollPosition(idType: EventID.self, edge: .bottom)

    /// A binding that reads and writes the box directly. It is rebuilt on each body pass,
    /// which is free: the closures capture the box, and the box is what survives.
    var binding: Binding<ScrollPosition> {
        Binding(get: { self.position }, set: { self.position = $0 })
    }
}
