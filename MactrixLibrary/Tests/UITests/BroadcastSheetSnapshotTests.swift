import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots of the broadcast sheet (MATRIX-168): the compose step, the
/// review step at 3 and at 21 targets (the typed count), a run in progress,
/// and a finished run with one failure. MATRIX-172: the compose step shows
/// the source line ("All 5 chats of Work"), and a list with missing chats
/// shows how many and why in the compose and the review steps.
///
/// The sheet has text fields, so every test uses `assertTextFieldSnapshot`.
/// The spinner uses the static stand-in. The loader has no image, so each
/// avatar draws its initials. Local gate only, as the other snapshots
/// (contract R-8).
@MainActor
struct BroadcastSheetSnapshotTests {
    /// Serves no image: the avatars draw their placeholders.
    private struct NoImageLoader: ImageLoader {
        func cachedImage(matrixUrl _: String) -> Image? {
            nil
        }

        func loadImage(matrixUrl _: String, size _: CGSize?) async throws -> Image? {
            nil
        }
    }

    private static let names = [
        "Design Team", "Seth Redacted", "Launch Planning", "Ana Example", "Support Rota", "Billing", "Bob Example",
        "Carol Example", "Dave Example", "Eve Example", "Frank Example", "Grace Example", "Heidi Example",
        "Ivan Example", "Judy Example", "Mallory Example", "Niaj Example", "Olivia Example", "Peggy Example",
        "Rupert Example", "Sybil Example",
    ]

    private func makeTargets(_ count: Int) -> [BroadcastTarget] {
        Self.names.prefix(count).enumerated().map { index, name in
            let id = "!room\(index):example.org"
            let row = ChatListRowModel(id: id, title: name, isDirect: name.hasSuffix("Example"), network: .slack)
            return BroadcastTarget(id: id, row: row, roomId: id)
        }
    }

    private func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(
            rootView: view
                .environment(\.usesStaticProgressIndicators, true)
                .environment(\.locale, Locale(identifier: "en_US"))
                .background(Color(NSColor.windowBackgroundColor))
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not flip with dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private func sheet(
        targets: [BroadcastTarget],
        gap: BroadcastTargetGap? = nil,
        draft: BroadcastDraft,
        typedCount: String = "",
        step: BroadcastSheetStep,
        states: [String: BroadcastTargetState] = [:],
        phase: BroadcastRun.Phase = .idle
    ) -> some View {
        BroadcastSheet(
            filterName: "Work",
            targets: targets,
            gap: gap,
            draft: .constant(draft),
            typedCount: .constant(typedCount),
            step: step,
            states: states,
            phase: phase,
            imageLoader: NoImageLoader(),
            actions: BroadcastSheetActions()
        )
    }

    private static let message = "The office is closed on Friday. **Please** move your meetings."

    private func makeDraft(_ targets: [BroadcastTarget]) -> BroadcastDraft {
        var draft = BroadcastDraft(targets: targets)
        draft.text = Self.message
        return draft
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func compose() {
        let targets = makeTargets(5)
        var draft = makeDraft(targets)
        draft.setSelected(false, id: targets[3].id)
        assertTextFieldSnapshot(of: host(sheet(targets: targets, draft: draft, step: .compose)), as: .scaledImage)
    }

    /// An empty draft: the placeholder shows and Review is disabled.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func composeEmpty() {
        let targets = makeTargets(3)
        assertTextFieldSnapshot(
            of: host(sheet(targets: targets, draft: BroadcastDraft(targets: targets), step: .compose)),
            as: .scaledImage
        )
    }

    /// MATRIX-172: the label names 2 chats the account's list does not hold.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func composeWithMissingChats() {
        let targets = makeTargets(5)
        let gap = BroadcastTargetGap(reason: .notInAccountList, count: 2)
        assertTextFieldSnapshot(
            of: host(sheet(targets: targets, gap: gap, draft: makeDraft(targets), step: .compose)),
            as: .scaledImage
        )
    }

    /// MATRIX-172: the review step repeats the missing chats.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func reviewWithMissingChats() {
        let targets = makeTargets(3)
        let gap = BroadcastTargetGap(reason: .accountListNotLoaded, count: nil)
        assertTextFieldSnapshot(
            of: host(sheet(targets: targets, gap: gap, draft: makeDraft(targets), step: .review)),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func reviewWithThreeTargets() {
        let targets = makeTargets(3)
        assertTextFieldSnapshot(of: host(sheet(targets: targets, draft: makeDraft(targets), step: .review)), as: .scaledImage)
    }

    /// Above 20 targets: the count field shows, and the send button is
    /// disabled until the count is typed.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func reviewWithTwentyOneTargets() {
        let targets = makeTargets(21)
        assertTextFieldSnapshot(of: host(sheet(targets: targets, draft: makeDraft(targets), step: .review)), as: .scaledImage)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func reviewWithTwentyOneTargetsConfirmed() {
        let targets = makeTargets(21)
        assertTextFieldSnapshot(
            of: host(sheet(targets: targets, draft: makeDraft(targets), typedCount: "21", step: .review)),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func sending() {
        let targets = makeTargets(4)
        let states: [String: BroadcastTargetState] = [
            targets[0].id: .sent, targets[1].id: .sending, targets[2].id: .waiting, targets[3].id: .waiting,
        ]
        assertTextFieldSnapshot(
            of: host(sheet(targets: targets, draft: makeDraft(targets), step: .progress, states: states, phase: .running)),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func finishedWithOneFailure() {
        let targets = makeTargets(4)
        let states: [String: BroadcastTargetState] = [
            targets[0].id: .sent,
            targets[1].id: .failed("The chat was not found."),
            targets[2].id: .sent,
            targets[3].id: .sent,
        ]
        assertTextFieldSnapshot(
            of: host(sheet(targets: targets, draft: makeDraft(targets), step: .progress, states: states, phase: .finished)),
            as: .scaledImage
        )
    }

    /// A stop left two targets out.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func finishedAfterStop() {
        let targets = makeTargets(4)
        let states: [String: BroadcastTargetState] = [targets[0].id: .sent, targets[1].id: .sent]
        assertTextFieldSnapshot(
            of: host(sheet(targets: targets, draft: makeDraft(targets), step: .progress, states: states, phase: .finished)),
            as: .scaledImage
        )
    }
}
