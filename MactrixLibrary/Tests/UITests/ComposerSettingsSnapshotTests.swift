import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots for Settings > Composer (MATRIX-100).
///
/// Each test reads the setting from its own `UserDefaults` suite, so the
/// snapshot never depends on what the test host's standard defaults hold, and
/// parallel tests never share state. The 450-point width matches the frame
/// `SettingsView` gives its tabs.
@MainActor
struct ComposerSettingsSnapshotTests {
    private func isolatedDefaults(
        suite: String,
        mode: ComposerKeyDecision.SendMode?
    ) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        if let mode {
            defaults.set(mode.rawValue, forKey: ComposerKeyDecision.SendMode.storageKey)
        }
        return defaults
    }

    private func assertPinnedSnapshot(
        of view: some View,
        testName: String = #function
    ) {
        let controller = NSHostingController(rootView: view.frame(width: 450).padding())
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance so the snapshot does not flip with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)

        assertSnapshot(of: controller, as: .scaledImage, testName: testName)
    }

    /// A user who never opened the tab sees the D-1 default selected.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func defaultModeSelected() throws {
        let defaults = try isolatedDefaults(suite: "ComposerSettingsSnapshotTests.default", mode: nil)
        assertPinnedSnapshot(of: ComposerSettingsView(store: defaults))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func commandEnterModeSelected() throws {
        let defaults = try isolatedDefaults(
            suite: "ComposerSettingsSnapshotTests.commandEnter",
            mode: .commandEnterSends
        )
        assertPinnedSnapshot(of: ComposerSettingsView(store: defaults))
    }
}
