import Core
@testable import MactrixiOS
import MatrixRustSDK
import XCTest

/// MATRIX-242: the chat list's sync line shows the Mac sidebar's text for
/// each `SyncStatusLine`, with Retry where the Mac shows "Restart sync".
@MainActor
final class RoomListSyncLineTests: XCTestCase {
    private static let allLines: [SyncStatusLine] = [.hidden, .connecting, .offline, .stopped, .error, .signedOut]

    func testNoLineWhileSyncRuns() {
        XCTAssertNil(RoomListSyncLineContent(.hidden))
    }

    private struct Expected {
        let line: SyncStatusLine
        let title: String
        let systemImage: String
    }

    func testEachLineHasTheMacText() throws {
        let expected = [
            Expected(line: .connecting, title: "Connecting…", systemImage: "arrow.triangle.2.circlepath"),
            Expected(line: .offline, title: "Offline", systemImage: "wifi.slash"),
            Expected(line: .stopped, title: "Sync stopped", systemImage: "wifi.slash"),
            Expected(line: .error, title: "Sync error", systemImage: "exclamationmark.triangle"),
            Expected(line: .signedOut, title: "Logged out", systemImage: "wifi.slash"),
        ]

        for item in expected {
            let content = try XCTUnwrap(RoomListSyncLineContent(item.line), "\(item.line)")
            XCTAssertEqual(String(localized: content.title), item.title, "\(item.line)")
            XCTAssertEqual(content.systemImage, item.systemImage, "\(item.line)")
        }
    }

    func testRetryShowsWhenSyncStoppedFailedOrIsOffline() throws {
        for line in [SyncStatusLine.offline, .stopped, .error] {
            XCTAssertTrue(try XCTUnwrap(RoomListSyncLineContent(line)).showsRetry, "\(line)")
        }
        for line in [SyncStatusLine.connecting, .signedOut] {
            XCTAssertFalse(try XCTUnwrap(RoomListSyncLineContent(line)).showsRetry, "\(line)")
        }
    }

    /// One rule with the Mac: Retry on iOS where the Mac shows Restart.
    func testRetryFollowsTheMacRestartRule() {
        for line in Self.allLines {
            XCTAssertEqual(RoomListSyncLineContent(line)?.showsRetry ?? false, line.canRestart, "\(line)")
        }
    }

    /// The line after a stop for the background: the service sent `running`
    /// before, and `stop()` made it `idle`.
    func testABackgroundStopShowsSyncStoppedWithRetry() throws {
        let line = SyncStatusLine(state: .idle, hasRun: true, startFailed: false)

        let content = try XCTUnwrap(RoomListSyncLineContent(line))

        XCTAssertEqual(String(localized: content.title), "Sync stopped")
        XCTAssertTrue(content.showsRetry)
    }
}
