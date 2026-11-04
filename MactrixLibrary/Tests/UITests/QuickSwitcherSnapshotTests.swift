import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
@testable import UI

/// Snapshots for the ⌘K quick switcher (MATRIX-114).
///
/// Each test renders the real sheet from a prepared query and directory
/// results. The search closure never runs: the capture is synchronous, so
/// the sheet's `.task` has not started when the image is taken.
@MainActor
struct QuickSwitcherSnapshotTests {
    private let rooms = [
        QuickSwitcherRoom(id: "!design", name: "Design Reviews", canonicalAlias: "#design:example.org", recencyRank: 0),
        QuickSwitcherRoom(
            id: "!alice", name: "Alice Liddell", isDirect: true, directUserId: "@alice:example.org", recencyRank: 1
        ),
        QuickSwitcherRoom(id: "!general", name: "General", canonicalAlias: "#general:example.org", recencyRank: 2),
        QuickSwitcherRoom(id: "!ops", name: "Ops Alerts", recencyRank: 3),
    ]

    private var actions: QuickSwitcherActions {
        .navigate(
            searchPeople: { _ in [] },
            openRoom: { _ in },
            startDirectChat: { _ in }
        )
    }

    private func host(query: String, directoryResults: [NewChatPerson] = []) -> NSViewController {
        let sheet = QuickSwitcherView(
            rooms: rooms,
            currentRoomId: "!general",
            ownUserId: "@patrick:davlin.io",
            imageLoader: nil,
            actions: actions,
            query: query,
            directoryResults: directoryResults
        )
        let controller = NSHostingController(rootView: sheet)
        controller.view.frame.size = CGSize(width: 560, height: 420)
        // Pin the appearance so the snapshot does not flip with light/dark mode.
        controller.view.appearance = NSAppearance(named: .aqua)
        return controller
    }

    /// Empty query: recent rooms, with the open room ("General") last.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func emptyQueryShowsRecentRooms() {
        assertSnapshot(of: host(query: ""), as: .scaledImage)
    }

    /// "ali": the DM room first, then people from the directory. Alice has a
    /// listed DM, so she is not repeated as a person.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil))
    func roomsAndPeople() {
        let people = [
            NewChatPerson(userId: "@alice:example.org", displayName: "Alice Liddell"),
            NewChatPerson(userId: "@alistair:example.org", displayName: "Alistair Reid"),
            NewChatPerson(userId: "@natalia:example.org", displayName: "Natalia Ali"),
        ]
        assertSnapshot(of: host(query: "ali", directoryResults: people), as: .scaledImage)
    }
}

/// MATRIX-114: picker mode hands the room back instead of opening it.
@MainActor
struct QuickSwitcherActionsTests {
    @Test func pickerHandsThePickedRoomToTheCaller() async throws {
        var picked: [String] = []
        let actions = QuickSwitcherActions.picker { picked.append($0) }

        #expect(actions.mode == .pickRoom)
        let room = QuickSwitcherRoom(id: "!target", name: "Target", recencyRank: 0)
        let decision = QuickSwitcherRanking.decide(.room(room), mode: actions.mode, key: .primary)
        let handler = try #require(actions.handler(for: decision))
        try await handler()

        #expect(picked == ["!target"])
    }

    @Test func pickerHasNoHandlerForOpenOrStart() {
        let actions = QuickSwitcherActions.picker { _ in }
        #expect(actions.handler(for: .openRoom(roomId: "!a")) == nil)
        #expect(actions.handler(for: .startDirectChat(userId: "@a:b")) == nil)
        #expect(actions.handler(for: .ignore) == nil)
    }

    @Test func optionReturnDoesNothingUntilTheNewWindowHookIsWired() async throws {
        var opened: [String] = []
        let actions = QuickSwitcherActions.navigate(
            searchPeople: { _ in [] },
            openRoom: { opened.append($0) },
            startDirectChat: { _ in }
        )
        #expect(actions.handler(for: .openRoomInNewWindow(roomId: "!a")) == nil)

        let open = try #require(actions.handler(for: .openRoom(roomId: "!a")))
        try await open()
        #expect(opened == ["!a"])
    }
}
