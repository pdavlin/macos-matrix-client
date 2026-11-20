import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// MATRIX-200: the Threads pane with rows, the empty state, and the loading
/// state, in light and dark.
///
/// Same capture as the other snapshots: a fixed 2x scale and a pinned
/// appearance, at the inspector's ideal width.
@MainActor
@Suite(.referenceScaleScreen)
struct ThreadListSnapshotTests {
    private nonisolated static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private static let now: Date = {
        let components = DateComponents(year: 2026, month: 11, day: 19, hour: 15, minute: 0)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    private static func message(
        _ id: String,
        user: String,
        name: String,
        isOwn: Bool = false,
        minutesAgo: Double,
        content: ChatListPreviewContent
    ) -> ThreadListMessage {
        ThreadListMessage(
            eventId: id,
            sender: ChatListSender(userId: user, displayName: name, isOwn: isOwn),
            avatarUrl: nil,
            date: now.addingTimeInterval(-minutesAgo * 60),
            content: content
        )
    }

    private static let entries: [ThreadListEntry] = [
        ThreadListEntry(
            root: message(
                "$1",
                user: "@ben:example.org",
                name: "Ben",
                minutesAgo: 300,
                content: .text(
                    "The nightly build failed on the snapshot step again. Can someone look at the runner image before the release cut?"
                )
            ),
            latestReply: message("$1r", user: "@cy:example.org", name: "Cy", minutesAgo: 18, content: .text("fixed, rerun now")),
            replyCount: 4
        ),
        ThreadListEntry(
            root: message("$2", user: "@ana:example.org", name: "Ana", minutesAgo: 1_600, content: .text("Lunch on Friday?")),
            latestReply: message(
                "$2r", user: "@me:example.org", name: "Me", isOwn: true, minutesAgo: 1_500, content: .text("yes, noon works")
            ),
            replyCount: 1
        ),
        ThreadListEntry(
            root: message("$3", user: "@dee:example.org", name: "Dee", minutesAgo: 6_000, content: .image),
            latestReply: nil,
            replyCount: 0
        ),
    ]

    private func host(
        _ content: ThreadListPaneContent,
        entries: [ThreadListEntry],
        appearance: NSAppearance.Name
    ) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                ThreadListView(
                    entries: entries,
                    content: content,
                    imageLoader: nil,
                    now: Self.now,
                    onOpen: { _ in },
                    onLoadMore: {},
                    onRetry: {}
                )
                .frame(width: 280, height: 320)
                .background(Color(NSColor.windowBackgroundColor))
            )
        )
        controller.view.frame.size = CGSize(width: 280, height: 320)
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private func name(_ appearance: NSAppearance.Name) -> String {
        appearance == .darkAqua ? "dark" : "light"
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func list(appearance: NSAppearance.Name) {
        assertSnapshot(
            of: host(.list(footer: .loading), entries: Self.entries, appearance: appearance),
            as: .scaledImage,
            named: name(appearance)
        )
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func empty(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(.empty, entries: [], appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func loading(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(.loading, entries: [], appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func failed(appearance: NSAppearance.Name) {
        let failed = ThreadListPaneContent.failed("The server did not answer.")
        assertSnapshot(of: host(failed, entries: [], appearance: appearance), as: .scaledImage, named: name(appearance))
    }
}
