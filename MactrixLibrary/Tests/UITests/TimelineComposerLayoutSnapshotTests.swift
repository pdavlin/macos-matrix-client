import AppKit
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// MATRIX-198: the timeline runs to the bottom edge and the glass composer
/// floats over it.
///
/// Opaque bars stand in for the timeline's rows. The layout hands the
/// timeline its bottom inset; the stand-in pads its rows by it at the bottom,
/// as the Mac timeline's scroll view does with its content inset, or lets
/// them run under the composer for a timeline scrolled up into its history.
/// Glass renders flat in an offscreen `NSHostingController`, and
/// `cacheDisplay` draws nothing for tinted glass, so the send capsule is
/// untinted (`untintedForSnapshot`). The glass over moving rows needs a look
/// in the app (contract R-8).
@MainActor
struct TimelineComposerLayoutSnapshotTests {
    private static let paneSize = NSSize(width: 420, height: 360)

    /// The last bottom inset the layout gave the timeline.
    private final class InsetProbe {
        var lastInset: CGFloat?
    }

    /// Opaque rows, newest at the bottom.
    private struct StandInTimeline: View {
        let bottomInset: CGFloat
        /// True: the rows rest above the composer. False: scrolled up, so
        /// rows run under the composer too.
        let isAtBottom: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Spacer(minLength: 0)
                ForEach(0 ..< 9, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 10)
                        .fill(index.isMultiple(of: 2) ? Color.blue : Color.orange)
                        .frame(width: index.isMultiple(of: 3) ? 300 : 220, height: 30)
                        .overlay(alignment: .leading) {
                            Text("Message \(index + 1)")
                                .foregroundStyle(.white)
                                .padding(.leading, 10)
                        }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, isAtBottom ? bottomInset : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .clipped()
        }
    }

    private func composer(text: String?, height: CGFloat? = nil) -> some View {
        ComposerChrome(
            hasContent: text != nil,
            canAttach: true,
            canPickEmoji: true,
            canSend: text != nil,
            isEditing: false,
            usesGlass: true,
            actions: .init(attach: {}, emoji: {}, send: {})
        ) {
            Text(text ?? "Message Seth")
                .foregroundStyle(text == nil ? .secondary : .primary)
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        }
        .untintedForSnapshot()
        // As `ChatInputView` pads it.
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func layout(
        isAtBottom: Bool,
        text: String?,
        fieldHeight: CGFloat? = nil,
        probe: InsetProbe? = nil
    ) -> some View {
        TimelineComposerLayout(
            isAtBottom: isAtBottom,
            unseenCount: isAtBottom ? 0 : 3,
            scrollToBottom: {},
            timeline: { bottomInset in
                probe?.lastInset = bottomInset
                return StandInTimeline(bottomInset: bottomInset, isAtBottom: isAtBottom)
            },
            composer: { composer(text: text, height: fieldHeight) }
        )
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func host(_ view: some View, appearance: NSAppearance.Name = .aqua) -> NSHostingController<AnyView> {
        let controller = NSHostingController(rootView: AnyView(view))
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: Self.paneSize)
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    /// Lets the measured composer height reach the layout's state, then lays
    /// out again.
    private func settle(_ controller: NSHostingController<AnyView>) async throws {
        for _ in 0 ..< 3 {
            try await Task.sleep(for: .milliseconds(50))
            controller.view.layoutSubtreeIfNeeded()
        }
    }

    // MARK: - Inset

    @Test
    func theInsetIsTheComposerAndTheGap() {
        #expect(TimelineComposerLayout<EmptyView, EmptyView>.bottomInset(composerHeight: 0) == 0)
        #expect(TimelineComposerLayout<EmptyView, EmptyView>.bottomInset(composerHeight: 54) == 62)
        #expect(TimelineComposerLayout<EmptyView, EmptyView>.gap == 8)
    }

    @Test
    func theTimelineGetsTheComposerHeightAndFollowsIt() async throws {
        let probe = InsetProbe()
        let controller = host(layout(isAtBottom: true, text: nil, fieldHeight: 40, probe: probe))
        try await settle(controller)
        let oneLine = try #require(probe.lastInset)
        // The field (40) and its 10 pt bottom padding, plus the gap.
        #expect(oneLine == 40 + 10 + TimelineComposerLayout<EmptyView, EmptyView>.gap)

        // More lines: the inset grows by the same amount.
        controller.rootView = AnyView(layout(isAtBottom: true, text: "Line\nLine\nLine", fieldHeight: 120, probe: probe))
        try await settle(controller)
        let multiLine = try #require(probe.lastInset)
        #expect(multiLine == 120 + 10 + TimelineComposerLayout<EmptyView, EmptyView>.gap)

        // And it shrinks back.
        controller.rootView = AnyView(layout(isAtBottom: true, text: nil, fieldHeight: 40, probe: probe))
        try await settle(controller)
        #expect(probe.lastInset == oneLine)
    }

    // MARK: - Snapshots

    /// At the bottom: the newest row rests above the composer.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func atBottomLight() async throws {
        let controller = host(layout(isAtBottom: true, text: nil))
        try await settle(controller)
        assertSnapshot(of: controller, as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func atBottomDark() async throws {
        let controller = host(layout(isAtBottom: true, text: nil), appearance: .darkAqua)
        try await settle(controller)
        assertSnapshot(of: controller, as: .scaledImage)
    }

    /// Scrolled up: rows run under the glass composer, and the chip sits
    /// above it.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func scrolledLight() async throws {
        let controller = host(layout(isAtBottom: false, text: "Lunch at noon?"))
        try await settle(controller)
        assertSnapshot(of: controller, as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func scrolledDark() async throws {
        let controller = host(layout(isAtBottom: false, text: "Lunch at noon?"), appearance: .darkAqua)
        try await settle(controller)
        assertSnapshot(of: controller, as: .scaledImage)
    }
}
