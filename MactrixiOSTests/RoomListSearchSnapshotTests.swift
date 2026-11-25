@testable import MactrixiOS
import Models
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

/// MATRIX-247: the chat search results, the empty search, and the Low
/// Priority list with its title and filter menu, in light and dark.
///
/// The references hold for one simulator runtime and device
/// (`SnapshotRuntime`, in `ThreadSnapshotTests.swift`); another runtime, as
/// on CI, skips these tests. To record again: delete
/// `__Snapshots__/RoomListSearchSnapshotTests`, run the tests one time (they
/// record and fail), then run them again.
@MainActor
final class RoomListSearchSnapshotTests: XCTestCase {
    private typealias Item = SampleRoomListItem

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(SnapshotRuntime.matchesReferences, SnapshotRuntime.skipReason)
    }

    // MARK: Search results

    func testSearchResultsLight() {
        assertSnapshot(of: list(searchResults: Self.results), as: image(.light), named: "light")
    }

    func testSearchResultsDark() {
        assertSnapshot(of: list(searchResults: Self.results), as: image(.dark), named: "dark")
    }

    func testNoSearchResults() {
        assertSnapshot(of: list(searchResults: []), as: image(.light), named: "light")
    }

    // MARK: Low Priority

    func testLowPriorityListLight() {
        assertSnapshot(of: lowPriorityShell(), as: image(.light), named: "light")
    }

    func testLowPriorityListDark() {
        assertSnapshot(of: lowPriorityShell(), as: image(.dark), named: "dark")
    }

    // MARK: - Views

    private static let results = [
        QuickSwitcherRoom(id: "!old", name: "Book club", canonicalAlias: "#books:example.org", recencyRank: 140),
        QuickSwitcherRoom(id: "!dm", name: "Bob (Signal)", isDirect: true, directUserId: "@signal_bob:example.org", recencyRank: 3),
        QuickSwitcherRoom(id: "!eng", name: "#backend (Slack)", recencyRank: 12),
    ]

    private func list(searchResults: [QuickSwitcherRoom]) -> some View {
        NavigationStack {
            RoomListView(
                chats: Item.all.map { RoomListChat.room($0) },
                searchResults: searchResults,
                isLoading: false,
                imageLoader: nil,
                selection: nil
            )
        }
        .frame(width: 390, height: 320)
    }

    private func lowPriorityShell() -> some View {
        RoomNavigationShell(
            rooms: [Item](),
            isLoading: false,
            imageLoader: nil,
            usesStack: true,
            filter: .constant(.lowPriority)
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
