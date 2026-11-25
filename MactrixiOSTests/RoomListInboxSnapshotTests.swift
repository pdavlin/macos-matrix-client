@testable import MactrixiOS
import Models
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

/// MATRIX-248: the chat list with a merged chat as one row, the Archived
/// list and its empty state, the Snoozed empty state, and the search
/// results with a merged chat and the archived and snoozed marks, in light
/// and dark.
///
/// The references hold for one simulator runtime and device
/// (`SnapshotRuntime`, in `ThreadSnapshotTests.swift`); another runtime, as
/// on CI, skips these tests. To record again: delete
/// `__Snapshots__/RoomListInboxSnapshotTests`, run the tests one time (they
/// record and fail), then run them again.
@MainActor
final class RoomListInboxSnapshotTests: XCTestCase {
    private typealias Item = SampleRoomListItem

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(SnapshotRuntime.matchesReferences, SnapshotRuntime.skipReason)
    }

    // MARK: Merged chat

    func testMergedChatRowLight() {
        assertSnapshot(of: inboxShell(), as: image(.light), named: "light")
    }

    func testMergedChatRowDark() {
        assertSnapshot(of: inboxShell(), as: image(.dark), named: "dark")
    }

    // MARK: Archived and Snoozed

    func testArchivedListLight() {
        assertSnapshot(of: archivedShell(), as: image(.light), named: "light")
    }

    func testArchivedListDark() {
        assertSnapshot(of: archivedShell(), as: image(.dark), named: "dark")
    }

    func testNoArchivedChats() {
        assertSnapshot(of: emptyShell(.archived), as: image(.light), named: "light")
    }

    func testNoSnoozedChats() {
        assertSnapshot(of: emptyShell(.snoozed), as: image(.light), named: "light")
    }

    // MARK: Search marks

    func testSearchResultsWithMarksLight() {
        assertSnapshot(of: searchList(), as: image(.light), named: "light")
    }

    func testSearchResultsWithMarksDark() {
        assertSnapshot(of: searchList(), as: image(.dark), named: "dark")
    }

    // MARK: - Views

    private static let rooms = Item.sethMembers + Item.all

    /// "!dm1" is archived; the merged chat with Seth is in the Inbox.
    private static var inbox: InboxStateDocument {
        var inbox = InboxStateDocument()
        inbox.archive(["!dm1"], at: Date(timeIntervalSince1970: 1_800_000_000))
        return inbox
    }

    private func inboxShell() -> some View {
        shell(filter: .inbox, chats: Item.chats(Self.rooms, inbox: Self.inbox))
    }

    private func archivedShell() -> some View {
        shell(filter: .archived, chats: Item.chats(Self.rooms, inbox: Self.inbox, filter: .archived))
    }

    private func emptyShell(_ filter: ChatListFilter) -> some View {
        shell(filter: filter, chats: [])
    }

    private func shell(filter: ChatListFilter, chats: [RoomListChat<Item>]) -> some View {
        RoomNavigationShell(
            rooms: Self.rooms,
            chats: chats,
            isLoading: false,
            imageLoader: nil,
            usesStack: true,
            filter: .constant(filter)
        ) { _ in
            EmptyView()
        }
        .frame(width: 390, height: 500)
    }

    /// The results as `ChatListSearch` builds them: the merged chat with
    /// Seth (snoozed), an archived room, and a room in the Inbox.
    private func searchList() -> some View {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let directory = [
            QuickSwitcherRoom(id: "!seth-wa", name: "Seth (WhatsApp)", isDirect: true, recencyRank: 0),
            QuickSwitcherRoom(id: "!seth-signal", name: "Seth (Signal)", isDirect: true, recencyRank: 4),
            QuickSwitcherRoom(id: "!sets", name: "Set designers", canonicalAlias: "#sets:example.org", recencyRank: 7),
            QuickSwitcherRoom(id: "!old", name: "Settlers book club", recencyRank: 140),
        ]
        var inbox = InboxStateDocument()
        inbox.archive(["!old"], at: now)
        inbox.snooze(["!seth-wa", "!seth-signal"], until: now.addingTimeInterval(3600), at: now)
        let results = ChatListSearch.results(
            in: directory,
            query: "set",
            merges: Item.sethMerge,
            inbox: inbox,
            now: now
        ) ?? []
        return NavigationStack {
            RoomListView(
                chats: Item.all.map { RoomListChat.room($0) },
                searchResults: results,
                isLoading: false,
                imageLoader: nil,
                selection: nil
            )
        }
        .frame(width: 390, height: 320)
    }

    /// A fixed light or dark appearance, so the image does not follow the
    /// simulator's.
    private func image<Content: View>(_ style: UIUserInterfaceStyle) -> Snapshotting<Content, UIImage> {
        .image(layout: .sizeThatFits, traits: UITraitCollection(userInterfaceStyle: style))
    }
}
