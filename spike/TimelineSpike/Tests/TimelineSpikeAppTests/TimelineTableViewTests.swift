import AppKit
import Foundation
import Testing
import TimelineSpikeCore
@testable import TimelineSpikeApp

/// Drives the real view in an off-screen window.
///
/// This is not a substitute for the scenarios in `spike/SCENARIOS.md`. It cannot measure a
/// frame time, it cannot scroll with a trackpad, and it cannot see. What it can do is check
/// the one property that decides whether the candidate is viable at all: that the content the
/// viewport is looking at does not move when events are prepended above it or when an
/// off-screen row changes height. Those are S4 and S2 reduced to arithmetic.
///
/// The window is borderless and never ordered front, so running the suite does not take focus.
@MainActor
@Suite("AppKit table anchoring", .serialized)
struct TimelineTableViewTests {
    private static let viewportSize = NSSize(width: 1080, height: 860)

    private func makeHarness(eventCount: Int = 2000) -> SpikeHarness {
        SpikeHarness(
            configuration: HarnessConfiguration(
                seed: HarnessConfiguration.default.seed,
                initialEventCount: eventCount,
                mutation: .default,
                // Manual prepends only: an automatic one firing mid-assertion would make the
                // test measure something other than what it claims to.
                pagination: PaginationDriverConfiguration(isAutomatic: false)
            )
        )
    }

    /// Returns the view and the window that owns it. The window must outlive the view, so the
    /// caller holds both.
    private func makeView(harness: SpikeHarness) -> (view: TimelineTableView, window: NSWindow) {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.viewportSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        // A programmatically created NSWindow releases itself on close, which would leave the
        // test holding a dangling reference.
        window.isReleasedWhenClosed = false
        let view = TimelineTableView(harness: harness)
        view.frame = NSRect(origin: .zero, size: Self.viewportSize)
        window.contentView?.addSubview(view)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        return (view, window)
    }

    /// The tracked row's distance from the top of the viewport, which is the number the
    /// `AnchorProbe` turns into drift.
    private func trackedOffset(_ harness: SpikeHarness) -> Double? {
        harness.probe.trackedOffset
    }

    @Test("The timeline opens at the newest event with a tracked row")
    func opensAtTheBottom() {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        #expect(!harness.probe.visibleIDs.isEmpty)
        #expect(harness.probe.visibleIDs.last == harness.store.items[harness.store.items.count - 1].id)
        #expect(harness.probe.trackedID != nil)
        #expect(trackedOffset(harness) != nil)
    }

    @Test("Twenty prepends do not move the tracked row")
    func prependsDoNotMoveTheContent() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        // Sit well inside the document so neither edge clamp is doing the work, the way S4
        // asks the operator to.
        rig.view.scrollViewport(toDistanceFromTop: 4000)
        rig.view.sync()

        var worst: Double = 0
        for _ in 0 ..< 20 {
            let before = try #require(trackedOffset(harness))
            let trackedBefore = try #require(harness.probe.trackedID)
            harness.prependNow()
            rig.view.sync()
            let after = try #require(trackedOffset(harness))
            #expect(harness.probe.trackedID == trackedBefore)
            worst = max(worst, abs(after - before))
        }
        #expect(worst <= 0.5)
    }

    @Test("A prepend at the very top of the loaded content still holds")
    func prependAtTheTop() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        rig.view.scrollViewport(toDistanceFromTop: 0)
        rig.view.sync()

        let before = try #require(trackedOffset(harness))
        harness.prependNow()
        rig.view.sync()
        let after = try #require(trackedOffset(harness))
        #expect(abs(after - before) <= 0.5)
        #expect(harness.store.oldestIndex == -50)
    }

    @Test("An off-screen edit above the viewport does not move the tracked row")
    func offScreenEditDoesNotMoveTheContent() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        rig.view.scrollViewport(toDistanceFromTop: 4000)
        rig.view.sync()

        let visible = try #require(harness.probe.visibleRange)
        let target = try #require(
            (0 ..< visible.lowerBound).last { harness.store.items[$0].event.content.isText }
        )
        let before = try #require(trackedOffset(harness))

        // A tall edit, so a renderer that fails to absorb it fails loudly.
        let body = TextBody(
            paragraphs: (0 ..< 6).map { "line \($0) " + String(repeating: "content ", count: 30) },
            lineCount: 24
        )
        harness.store.apply(.editText(harness.store.items[target].id, newBody: body))
        rig.view.sync()

        let after = try #require(trackedOffset(harness))
        #expect(abs(after - before) <= 0.5)
    }

    @Test("An off-screen edit below the viewport does not move the tracked row either")
    func belowScreenEditDoesNotMoveTheContent() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        rig.view.scrollViewport(toDistanceFromTop: 4000)
        rig.view.sync()

        let visible = try #require(harness.probe.visibleRange)
        let target = try #require(
            (visible.upperBound ..< harness.store.items.count)
                .first { harness.store.items[$0].event.content.isText }
        )
        let before = try #require(trackedOffset(harness))

        let body = TextBody(
            paragraphs: (0 ..< 6).map { "line \($0) " + String(repeating: "content ", count: 30) },
            lineCount: 24
        )
        harness.store.apply(.editText(harness.store.items[target].id, newBody: body))
        rig.view.sync()

        let after = try #require(trackedOffset(harness))
        #expect(abs(after - before) <= 0.5)
    }

    @Test("A storm of off-screen edits leaves the viewport exactly where it was")
    func offScreenStormDoesNotDrift() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        rig.view.scrollViewport(toDistanceFromTop: 4000)
        rig.view.sync()

        // Only off-screen targets, above and below in turn. On-screen rows are excluded on
        // purpose: a visible message that grows really does push the rows under it down, and a
        // renderer that hid that would be lying to the reader, not anchoring.
        var worst: Double = 0
        for step in 0 ..< 20 {
            let visible = try #require(harness.probe.visibleRange)
            let candidates: [Int] = step.isMultiple(of: 2)
                ? Array((0 ..< visible.lowerBound).reversed())
                : Array(visible.upperBound ..< harness.store.items.count)
            let target = try #require(
                candidates.dropFirst(step).first { harness.store.items[$0].event.content.isText }
            )

            let before = try #require(trackedOffset(harness))
            let body = TextBody(
                paragraphs: (0 ... step % 5).map { "para \($0) " + String(repeating: "word ", count: 40) },
                lineCount: 8
            )
            harness.store.apply(.editText(harness.store.items[target].id, newBody: body))
            rig.view.sync()
            let after = try #require(trackedOffset(harness))
            worst = max(worst, abs(after - before))
        }
        #expect(worst <= 0.5)
    }

    @Test("A visible message that grows moves the rows under it, and only those")
    func onScreenGrowthIsNotHidden() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        rig.view.scrollViewport(toDistanceFromTop: 4000)
        rig.view.sync()

        let visible = try #require(harness.probe.visibleRange)
        let tracked = try #require(harness.probe.trackedID)
        let trackedIndex = try #require(harness.store.itemIndex(for: tracked))
        // A row that is on screen and below the tracked row: growing it must not move the
        // tracked row at all.
        let below = try #require(
            (trackedIndex + 1 ..< visible.upperBound)
                .first { harness.store.items[$0].event.content.isText }
        )
        let before = try #require(trackedOffset(harness))
        let body = TextBody(
            paragraphs: (0 ..< 4).map { "para \($0) " + String(repeating: "word ", count: 40) },
            lineCount: 12
        )
        harness.store.apply(.editText(harness.store.items[below].id, newBody: body))
        rig.view.sync()
        #expect(abs(try #require(trackedOffset(harness)) - before) <= 0.5)
    }

    @Test("The visible set the probe receives matches what the table says is on screen")
    func visibleSetIsReported() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        rig.view.scrollViewport(toDistanceFromTop: 4000)
        rig.view.sync()

        let range = try #require(harness.probe.visibleRange)
        #expect(range.count == harness.probe.visibleIDs.count)
        #expect(harness.probe.visibleIDs.first == harness.store.items[range.lowerBound].id)
        #expect(harness.probe.visibleIDs.last == harness.store.items[range.upperBound - 1].id)

        // The viewport is 860pt tall, so a screenful is tens of rows, not hundreds.
        #expect(range.count > 1)
        #expect(range.count < 200)
    }

    @Test("Row indices keep pointing at the same events across prepends")
    func rowMappingSurvivesPrepends() throws {
        let harness = makeHarness()
        let rig = makeView(harness: harness)
        defer { rig.window.close() }

        rig.view.scrollViewport(toDistanceFromTop: 4000)
        rig.view.sync()
        let idsBefore = harness.probe.visibleIDs

        for _ in 0 ..< 3 {
            harness.prependNow()
            rig.view.sync()
        }

        #expect(harness.probe.visibleIDs == idsBefore)
        let range = try #require(harness.probe.visibleRange)
        #expect(harness.store.items[range.lowerBound].id == idsBefore.first)
    }
}
