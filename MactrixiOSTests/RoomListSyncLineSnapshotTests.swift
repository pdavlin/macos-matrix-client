import Core
@testable import MactrixiOS
import Models
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

/// MATRIX-242: the chat list's sync line at the bottom of the list: "Sync
/// stopped" and "Offline" with Retry, "Connecting…" with no button, and no
/// line while sync runs, in light and dark.
///
/// The references hold for one simulator runtime and device
/// (`SnapshotRuntime`, in `ThreadSnapshotTests.swift`); another runtime, as
/// on CI, skips these tests. To record again: delete
/// `__Snapshots__/RoomListSyncLineSnapshotTests`, run the tests one time
/// (they record and fail), then run them again.
@MainActor
final class RoomListSyncLineSnapshotTests: XCTestCase {
    private typealias Item = SampleRoomListItem

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(SnapshotRuntime.matchesReferences, SnapshotRuntime.skipReason)
    }

    func testSyncStoppedLight() {
        assertSnapshot(of: shell(.stopped), as: image(.light), named: "light")
    }

    func testSyncStoppedDark() {
        assertSnapshot(of: shell(.stopped), as: image(.dark), named: "dark")
    }

    func testOfflineLight() {
        assertSnapshot(of: shell(.offline), as: image(.light), named: "light")
    }

    func testConnectingLight() {
        assertSnapshot(of: shell(.connecting), as: image(.light), named: "light")
    }

    /// Sync runs: the list has no line.
    func testNoLineWhileSyncRuns() {
        assertSnapshot(of: shell(.hidden), as: image(.light), named: "light")
    }

    // MARK: - Views

    private func shell(_ line: SyncStatusLine) -> some View {
        RoomNavigationShell(
            rooms: Item.all,
            isLoading: false,
            imageLoader: nil,
            usesStack: true,
            filter: .constant(.inbox),
            sync: RoomListSync(line: line) {}
        ) { _ in
            EmptyView()
        }
        .frame(width: 390, height: 500)
    }

    /// A fixed light or dark appearance, so the image does not follow the
    /// simulator's.
    private func image<Content: View>(_ style: UIUserInterfaceStyle) -> Snapshotting<Content, UIImage> {
        .image(layout: .sizeThatFits, traits: UITraitCollection(userInterfaceStyle: style))
    }
}
