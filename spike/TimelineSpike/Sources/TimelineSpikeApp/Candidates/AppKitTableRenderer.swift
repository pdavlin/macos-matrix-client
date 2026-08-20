import AppKit
import SwiftUI
import TimelineSpikeCore

/// Candidate B (S-14): `NSTableView` in an `NSViewRepresentable`, with SwiftUI rows.
///
/// The list is AppKit — recycling, height bookkeeping, scroll position — and the row is the
/// same `SpikeRowView` the SwiftUI candidate draws, hosted per row. See `TimelineTableView`
/// for the architecture and `SpikeRowHostingView` for what the hosting costs.
struct AppKitTableRenderer: TimelineRenderer {
    nonisolated static let rendererID = "appkit-table"
    nonisolated static let displayName = "AppKit NSTableView"
    nonisolated static let summary =
        "NSTableView with a measured height cache, manual prepend anchoring, and SwiftUI rows in NSHostingViews."

    private let harness: SpikeHarness

    init(harness: SpikeHarness) {
        self.harness = harness
    }

    var body: some View {
        TimelineTableRepresentable(
            harness: harness,
            revision: StoreRevision(store: harness.store)
        )
    }
}

/// What the representable watches.
///
/// `NSViewRepresentable` has no `body`, so it cannot register with Observation on its own.
/// Building this token in `AppKitTableRenderer.body` reads the store's observable properties
/// there, which is what makes SwiftUI re-evaluate the renderer — and therefore call
/// `updateNSView` — on every mutation tick and every prepend.
///
/// Note what is *not* here: no throttle, no coalescing, no diffing. Every store change
/// reaches `TimelineTableView.sync()`.
struct StoreRevision: Equatable {
    let storeID: ObjectIdentifier
    let itemCount: Int
    let oldestIndex: Int
    let mutationCount: Int
    let prependedEventCount: Int

    @MainActor
    init(store: TimelineStore) {
        self.storeID = ObjectIdentifier(store)
        self.itemCount = store.items.count
        self.oldestIndex = store.oldestIndex
        self.mutationCount = store.appliedMutationCount
        self.prependedEventCount = store.prependedEventCount
    }
}

struct TimelineTableRepresentable: NSViewRepresentable {
    let harness: SpikeHarness
    let revision: StoreRevision

    func makeNSView(context _: Context) -> TimelineTableView {
        TimelineTableView(harness: harness)
    }

    func updateNSView(_ nsView: TimelineTableView, context _: Context) {
        nsView.sync()
    }
}
