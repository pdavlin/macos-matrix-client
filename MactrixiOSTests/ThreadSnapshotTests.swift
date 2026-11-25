@testable import MactrixiOS
import Models
import SnapshotTesting
import SwiftUI
import Tokens
import UIKit
import XCTest

/// MATRIX-245: the iOS thread chip on a root row, and the thread screen's
/// title, in light and dark.
///
/// The row is the iOS `TimelineRowContent` that a cell draws, on its non-SDK
/// path (an SDK item cannot be built in a test). Both paths draw the chip
/// with the same shared view and the same rule (`ThreadRootRule.showsChip`).
///
/// Pixels differ between simulator runtimes, so the references hold for the
/// runtime and device they were recorded on (`SnapshotRuntime`). Another
/// runtime, as on CI, skips these tests, as the Mac snapshot tests skip on
/// CI. To record again: delete `__Snapshots__/ThreadSnapshotTests`, run the
/// tests one time (they record and fail), then update `SnapshotRuntime`.
@MainActor
final class ThreadSnapshotTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(SnapshotRuntime.matchesReferences, SnapshotRuntime.skipReason)
    }

    // MARK: Chip on a root row

    func testChipOnRootRowLight() {
        assertSnapshot(of: rootRow(), as: image(.light), named: "light")
    }

    func testChipOnRootRowDark() {
        assertSnapshot(of: rootRow(), as: image(.dark), named: "dark")
    }

    // MARK: Thread screen title

    func testThreadScreenTitleLight() {
        assertSnapshot(of: title(), as: image(.light), named: "light")
    }

    func testThreadScreenTitleDark() {
        assertSnapshot(of: title(), as: image(.dark), named: "dark")
    }

    /// The thread still loads: the room name only.
    func testThreadScreenTitleWhileLoading() {
        assertSnapshot(of: title(replyCount: nil), as: image(.light), named: "light")
    }

    // MARK: - Views

    private func rootRow() -> some View {
        let event = ThreadRootEvent()
        return TimelineRowContent(
            row: event.row,
            showsSenderHeader: true,
            context: TimelineRowContext(
                timeline: nil,
                imageLoader: nil,
                ownUserId: "@me:example.org",
                showsReadReceipts: false,
                typography: TimelineTypography(base: 15),
                retryPagination: {}
            )
        )
        .frame(width: 390)
        .background(Color(.systemBackground))
    }

    private func title(replyCount: Int? = 4) -> some View {
        ThreadScreenTitle(roomName: "#general", replyCount: replyCount)
            .padding(8)
            .frame(width: 280)
            .background(Color(.systemBackground))
    }

    /// A fixed light or dark appearance, so the image does not follow the
    /// simulator's.
    private func image<Content: View>(_ style: UIUserInterfaceStyle) -> Snapshotting<Content, UIImage> {
        .image(layout: .sizeThatFits, traits: UITraitCollection(userInterfaceStyle: style))
    }
}

/// The runtime and device that recorded the references.
enum SnapshotRuntime {
    static let systemVersion = "27.0"
    static let deviceName = "iPhone 17"

    static var matchesReferences: Bool {
        runSystemVersion == systemVersion && runDeviceName == deviceName
    }

    static var skipReason: String {
        let run = "iOS \(runSystemVersion) on \(runDeviceName ?? "no simulator")"
        return "references are from iOS \(systemVersion) on \(deviceName), this run is \(run)"
    }

    private static var runSystemVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion)"
    }

    private static var runDeviceName: String? {
        ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
    }
}

/// A thread summary with a fixed count, latest reply, and repliers.
private struct StubThreadSummary: Models.ThreadSummary {
    func numReplies() -> UInt64 {
        4
    }

    var description: String? { "fixed, rerun now" }

    var repliers: [ThreadReplier] {
        [
            ThreadReplier(userId: "@cy:example.org", displayName: "Cy", avatarUrl: nil),
            ThreadReplier(userId: "@ana:example.org", displayName: "Ana", avatarUrl: nil),
        ]
    }
}

/// A thread root message with a fixed sender, time, and body.
private struct ThreadRootEvent: TimelineTextEvent {
    var body: String { "The deploy failed on the second step." }
    var formattedBody: String? { nil }
    var media: TimelineMedia? { nil }
    var quotedReply: ComposerReply? { nil }
    var reactionPills: [TimelineReactionPill] { [] }
    var threadSummary: (any Models.ThreadSummary)? { StubThreadSummary() }

    var isRemote: Bool { true }
    var sender: String { "@ben:example.org" }
    var senderProfileDetails: ProfileDetails { .ready(displayName: "Ben", displayNameAmbiguous: false, avatarUrl: nil) }
    var isOwn: Bool { false }
    var isEditable: Bool { false }
    var date: Date {
        let components = DateComponents(year: 2026, month: 11, day: 25, hour: 10, minute: 42)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    var sendState: LocalSendState? { nil }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { true }
    var userId: String { "@ben:example.org" }
    var displayName: String? { "Ben" }
    var avatarUrl: String? { nil }

    var row: TimelineRow {
        .message(
            uniqueId: "$root",
            event: self,
            kind: .text,
            heightFingerprint: TimelineRowHeightFingerprint(
                body: MessageBodyGeometry(variant: "text", text: body),
                hasThreadSummary: true,
                senderName: "Ben",
                reactions: ReactionStripGeometry(pills: [], hasReadReceipts: false)
            )
        )
    }
}
