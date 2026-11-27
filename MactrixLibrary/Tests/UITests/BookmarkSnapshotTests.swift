import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

private struct BookmarkRowEvent: Models.EventTimelineItem {
    let date: Date

    var sender: String { "@ada:example.org" }
    var isOwn: Bool { false }
    var isRemote: Bool { true }
    var senderProfileDetails: ProfileDetails { .ready(displayName: "Ada Lovelace", displayNameAmbiguous: false, avatarUrl: nil) }
    var isEditable: Bool { false }
    var sendState: LocalSendState? { nil }
    var localCreatedAt: UInt64? { nil }
    var userReadReceipts: [String: Receipt] { [:] }
    var canBeRepliedTo: Bool { true }
    var userId: String { sender }
    var displayName: String? { "Ada Lovelace" }
    var avatarUrl: String? { nil }
}

/// MATRIX-208: the bookmark mark on a timeline row and the Bookmarks list.
///
/// Dates are built in the machine's own calendar, so the timestamp column
/// reads the same wall-clock time in any zone. The list gets fixed time
/// text. No image loader, so every avatar is the initials placeholder.
/// References render at a fixed 2x through `.scaledImage` with the light
/// appearance pinned (contract R-8).
@MainActor
struct BookmarkSnapshotTests {
    /// 09:41 local on a fixed day.
    private static let date: Date = {
        let components = DateComponents(year: 2026, month: 11, day: 19, hour: 9, minute: 41)
        return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }()

    private func snapshot(of view: some View, width: CGFloat? = nil) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                view
                    .frame(width: width)
                    .background(Color(NSColor.controlBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    private func row(bookmarked: Bool) -> some View {
        MessageEventBodyView(
            event: BookmarkRowEvent(date: Self.date),
            focused: false,
            reactions: [MockReaction](),
            actions: MockMessageEventActions(),
            ownUserID: "@patrick:example.org",
            imageLoader: nil,
            roomMembers: [MockRoomMember]()
        ) {
            Text("The engine notes are in the shared folder.")
        }
        .environment(\.timelineRowIsBookmarked, bookmarked)
    }

    /// The second row is bookmarked: the mark sits before its time.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func bookmarkMarkBesideTheTime() {
        let view = VStack(spacing: 0) {
            row(bookmarked: false)
            row(bookmarked: true)
        }
        assertSnapshot(of: snapshot(of: view, width: 420), as: .scaledImage)
    }

    /// The mark is an overlay: the row height does not change.
    @Test func bookmarkMarkKeepsTheRowHeight() {
        let plain = snapshot(of: row(bookmarked: false), width: 420).view.fittingSize
        let marked = snapshot(of: row(bookmarked: true), width: 420).view.fittingSize
        #expect(plain == marked)
    }

    private static func listRows() -> [BookmarkListRow] {
        var document = BookmarkDocument()
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let keys = [
            BookmarkKey(roomId: "!design:davlin.io", eventId: "$1"),
            BookmarkKey(roomId: "!seth:davlin.io", eventId: "$2"),
            BookmarkKey(roomId: "!old:davlin.io", eventId: "$3"),
            BookmarkKey(roomId: "!new:davlin.io", eventId: "$4"),
        ]
        for (index, key) in keys.enumerated() {
            document.setBookmarked(key, true, savedAt: base.addingTimeInterval(TimeInterval(index)))
        }
        func room(_ title: String, _ id: String) -> BookmarkListRow.Room {
            BookmarkListRow.Room(title: title, avatarUrl: nil, initials: .room(title: title, roomId: id))
        }
        return BookmarkListRow.rows(
            for: document,
            rooms: [
                "!design:davlin.io": room("Design Review", "!design:davlin.io"),
                "!seth:davlin.io": room("Seth Redacted", "!seth:davlin.io"),
                "!new:davlin.io": room("Launch Plans", "!new:davlin.io"),
            ],
            messages: [
                keys[0]: .some(BookmarkListRow.Message(
                    senderName: "Ada Lovelace",
                    preview: "The sidebar spacing should match the chat list, and the tiles should start at the avatar edge.",
                    date: base
                )),
                keys[1]: .some(BookmarkListRow.Message(senderName: "Seth", preview: "Photo", date: base)),
                keys[2]: nil,
            ]
        )
    }

    /// Newest saved first: a loading row, an unavailable row with Remove,
    /// then two messages, one of them truncated.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func bookmarkList() {
        let view = BookmarkListView(
            rows: Self.listRows(),
            imageLoader: nil,
            timeText: { _ in "Yesterday" },
            open: { _ in },
            remove: { _ in }
        )
        assertSnapshot(of: snapshot(of: view), as: .scaledImage)
    }

    /// MATRIX-267: macOS 27.3 (26C5047e) puts the content of a
    /// `ContentUnavailableView(_:systemImage:description:)` 9 pt lower in
    /// the same frame than 26C5035r did, so this was recorded again. No
    /// tolerance: the empty state is the subject, and the move changes 3 %
    /// of the pixels.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func emptyBookmarkList() {
        let view = BookmarkListView(rows: [], imageLoader: nil, open: { _ in }, remove: { _ in })
        assertSnapshot(of: snapshot(of: view), as: .scaledImage)
    }
}
