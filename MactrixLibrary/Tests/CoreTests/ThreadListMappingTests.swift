@testable import Core
import Foundation
import MatrixRustSDK
import Models
import Testing

/// MATRIX-200: the SDK's thread-list types, mapped to the app models.
struct ThreadListMappingTests {
    private static func event(_ id: String, sender: String = "@ana:example.org", ms: UInt64 = 2_000) -> ThreadListItemEvent {
        ThreadListItemEvent(
            eventId: id,
            timestamp: ms,
            sender: sender,
            senderProfile: .ready(displayName: "Ana", displayNameAmbiguous: false, avatarUrl: "mxc://example.org/a", status: nil, call: nil),
            isOwn: false,
            content: nil
        )
    }

    private static func item(_ id: String, replies: UInt32 = 2) -> ThreadListItem {
        ThreadListItem(rootEvent: event(id), latestEvent: event("\(id)-r", ms: 9_000), numReplies: replies)
    }

    @Test func itemMapsToAnEntry() {
        let entry = ThreadListEntry(Self.item("$root", replies: 4))
        #expect(entry.id == "$root")
        #expect(entry.replyCount == 4)
        #expect(entry.root.sender.name == "Ana")
        #expect(entry.root.avatarUrl == "mxc://example.org/a")
        #expect(entry.root.date == Date(timeIntervalSince1970: 2))
        #expect(entry.latestReply?.eventId == "$root-r")
        #expect(entry.lastActivity == Date(timeIntervalSince1970: 9))
    }

    @Test func updatesReplayInOrder() {
        var list: [ThreadListEntry] = []
        let updates: [ThreadListUpdate] = [
            .reset(values: [Self.item("$a"), Self.item("$b")]),
            .pushFront(value: Self.item("$new")),
            .set(index: 2, value: Self.item("$b", replies: 7)),
            .remove(index: 2),
            .insert(index: 0, value: Self.item("$b", replies: 7)),
        ]
        for update in updates {
            let applied = list.apply(update.asModel)
            #expect(applied)
        }
        #expect(list.map(\.id) == ["$b", "$new", "$a"])
        #expect(list[0].replyCount == 7)
    }

    @Test func paginationStateMaps() {
        #expect(MatrixRustSDK.ThreadListPaginationState.loading.asModel == .loading)
        #expect(MatrixRustSDK.ThreadListPaginationState.idle(endReached: true).asModel == .idle(endReached: true))
    }
}
