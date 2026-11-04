import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots for the New Chat screen (MATRIX-75).
///
/// Each test renders the real screen from a prepared draft. The search,
/// profile, start, and join closures never run: the capture is synchronous,
/// so the screen's `.task` has not started when the image is taken.
@MainActor
struct NewChatSnapshotTests {
    private let alice = NewChatPerson(userId: "@alice:example.org", displayName: "Alice Liddell")
    private let bob = NewChatPerson(userId: "@bob:example.org", displayName: "Bob")
    private let puppet = NewChatPerson(userId: "@slack_u024be7lh:davlin.io", displayName: "Sam (Slack)")

    private var actions: NewChatActions {
        NewChatActions(
            search: { _ in [] },
            resolveProfile: { NewChatPerson(userId: $0) },
            start: { _ in },
            join: { _ in }
        )
    }

    private func host(mode: NewChatMode, draft: NewChatDraft = NewChatDraft()) -> NSViewController {
        let screen = NewChatScreen(
            mode: .constant(mode),
            recentContacts: [alice, bob],
            ownUserId: "@patrick:davlin.io",
            imageLoader: nil,
            actions: actions,
            draft: draft
        )
        let controller = NSHostingController(rootView: screen)
        controller.view.frame.size = CGSize(width: 560, height: 420)
        // Pin the appearance so the snapshot does not flip with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// Empty query: the leading actions, then recent DM partners.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func emptyStateWithLeadingActions() {
        assertSnapshot(of: host(mode: .direct), as: .scaledImage)
    }

    /// A typed user ID the directory does not return still gets a row of its
    /// own, first, so a bridge bot can be messaged.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func searchResultsWithExactUserIdRow() {
        let draft = NewChatDraft(query: "@slackbot:davlin.io", searchResults: [puppet])
        assertSnapshot(of: host(mode: .direct, draft: draft), as: .scaledImage)
    }

    /// One pill selected: the person leaves the list and Start is enabled.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func onePersonSelected() {
        let draft = NewChatDraft(selected: [alice])
        assertSnapshot(of: host(mode: .direct, draft: draft), as: .scaledImage)
    }

    /// Group mode with a name, showing the encryption confirm.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func groupModeWithEncryptionConfirm() {
        let draft = NewChatDraft(selected: [alice, bob], groupName: "Weekend plans", isConfirmingEncryption: true)
        assertSnapshot(of: host(mode: .group, draft: draft), as: .scaledImage)
    }

    /// Join mode after a failed join.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func joinModeWithError() {
        let draft = NewChatDraft(joinAddress: "#nowhere:example.org", errorMessage: NewChatScreen.joinErrorMessage)
        assertSnapshot(of: host(mode: .join, draft: draft), as: .scaledImage)
    }
}
