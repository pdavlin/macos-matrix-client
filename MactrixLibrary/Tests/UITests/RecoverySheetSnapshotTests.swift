import AppKit
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots for the recovery sheets.
///
/// These are the agent's only eyes on this UI (contract R-8). The key-display
/// sheet is the highest-stakes view in S-25: the SDK returns a recovery key
/// exactly once, so a layout that hides the key, or that lets the sheet be
/// dismissed before the user has saved it, loses the account's history.
///
/// The sheets live in the UI library rather than the app target precisely so
/// these tests exercise the real views. An earlier draft snapshotted a
/// duplicate declared in the test file, which would have kept passing while
/// the shipped view drifted.
@MainActor
struct RecoverySheetSnapshotTests {
    private func host(_ view: some View) -> NSViewController {
        let controller = NSHostingController(rootView: view)
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance for the same reason RoomEncryptionBadge does:
        // otherwise the snapshot flips with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// A key-shaped string, not a real one.
    private let sampleKey = "EsTb ABCD efGH 1234 ijKL 5678 mnOP 9012 qrST"

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func keyDisplay() {
        assertSnapshot(
            of: host(RecoveryKeyDisplaySheet(recoveryKey: sampleKey, onAcknowledge: {})),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func keyEntryEmpty() {
        assertSnapshot(
            of: host(RecoveryKeyEntrySheet(isBusy: false, errorMessage: nil, onSubmit: { _ in }, onCancel: {})),
            as: .scaledImage
        )
    }

    /// A wrong key is the common case, so the error has to be legible and must
    /// not push the buttons off the sheet.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func keyEntryShowingError() {
        assertSnapshot(
            of: host(RecoveryKeyEntrySheet(
                isBusy: false,
                errorMessage: "The recovery key is not valid. Check for missing characters and try again.",
                onSubmit: { _ in },
                onCancel: {}
            )),
            as: .scaledImage
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func keyEntryBusy() {
        assertSnapshot(
            of: host(RecoveryKeyEntrySheet(isBusy: true, errorMessage: nil, onSubmit: { _ in }, onCancel: {})),
            as: .scaledImage
        )
    }

    // MARK: - Identity Reset Banner (S-24)

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func identityResetBanner() {
        assertSnapshot(
            of: host(IdentityResetBanner(onVerify: {}, onSignOut: {})),
            as: .scaledImage
        )
    }
}
