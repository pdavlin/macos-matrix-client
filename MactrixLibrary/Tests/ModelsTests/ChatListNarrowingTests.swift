import Foundation
@testable import Models
import Testing

/// MATRIX-235: the rooms the SDK chat list is narrowed to for each list
/// filter (`ChatListFilter.narrowingRoomIds(rail:placementRoomIds:draftRoomIds:)`).
/// The Archived filter must list a chat after its archive.
struct ChatListNarrowingTests {
    private static let base = Date(timeIntervalSince1970: 1_800_000_000)
    private static let merges = MergedChatDocument(merges: [MergedChat(id: "m-seth", name: "Seth", rooms: ["!s1", "!s2"])])

    private func time(_ minutes: Double) -> Date {
        Self.base.addingTimeInterval(minutes * 60)
    }

    private func narrowing(
        _ filter: ChatListFilter,
        rail: [String]?,
        inbox: InboxStateDocument,
        drafts: Set<String> = []
    ) -> [String]? {
        filter.narrowingRoomIds(
            rail: rail,
            placementRoomIds: { inbox.roomIds(in: $0, merges: Self.merges) },
            draftRoomIds: { drafts }
        )
    }

    @Test
    func archivedFilterNarrowsTheListToAChatAfterItsArchive() {
        var inbox = InboxStateDocument()
        #expect(narrowing(.archived, rail: nil, inbox: inbox) == [])
        inbox.archive(["!b"], at: time(0))
        #expect(narrowing(.archived, rail: nil, inbox: inbox) == ["!b"])
        inbox.archive(["!s1", "!s2"], at: time(1))
        #expect(narrowing(.archived, rail: nil, inbox: inbox) == ["!b", "!s1", "!s2"])
    }

    @Test
    func archivedFilterKeepsOnlyTheRailFiltersArchivedChats() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a", "!b"], at: time(0))
        #expect(narrowing(.archived, rail: ["!c", "!b"], inbox: inbox) == ["!b"])
        #expect(narrowing(.archived, rail: ["!c"], inbox: inbox) == [])
        #expect(narrowing(.snoozed, rail: nil, inbox: inbox) == [])
    }

    @Test
    func inboxFiltersKeepTheRailNarrowing() {
        var inbox = InboxStateDocument()
        inbox.archive(["!a"], at: time(0))
        #expect(narrowing(.inbox, rail: nil, inbox: inbox) == nil)
        #expect(narrowing(.unread, rail: ["!c", "!a"], inbox: inbox) == ["!c", "!a"])
    }

    @Test
    func draftsFilterNarrowsTheListToTheDraftRooms() {
        let inbox = InboxStateDocument()
        #expect(narrowing(.drafts, rail: nil, inbox: inbox, drafts: ["!d", "!a"]) == ["!a", "!d"])
        #expect(narrowing(.drafts, rail: ["!a", "!c"], inbox: inbox, drafts: ["!d", "!a"]) == ["!a"])
    }
}
