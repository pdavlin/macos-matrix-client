@testable import Core
import Foundation
import MatrixRustSDK
import Models
import Testing

/// MATRIX-224: the own reaction marks store, the draft cache, and the SDK
/// mapping of the new list filters.
@MainActor
struct ChatListRowDetailsCoreTests {
    private static let alice = "@alice:example.org"

    private func defaults() throws -> UserDefaults {
        let suite = "MATRIX-224-\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    private func mark(secondsAgo: Double) -> ChatListMessageKey {
        ChatListMessageKey(senderId: Self.alice, timestamp: Date(timeIntervalSince1970: 1_800_000_000 - secondsAgo))
    }

    // MARK: Own reaction marks

    @Test
    func marksSurviveARelaunch() throws {
        let defaults = try defaults()
        let store = OwnReactionMarks(defaults: defaults, key: "marks")
        store.record(mark(secondsAgo: 0), roomId: "!a")
        let relaunched = OwnReactionMarks(defaults: defaults, key: "marks")
        #expect(relaunched.marks["!a"] == mark(secondsAgo: 0))
    }

    @Test
    func nilRemovesTheMark() throws {
        let store = try OwnReactionMarks(defaults: defaults(), key: "marks")
        store.record(mark(secondsAgo: 0), roomId: "!a")
        store.record(nil, roomId: "!a")
        #expect(store.marks.isEmpty)
    }

    @Test
    func oldestMarkGoesPastTheLimit() throws {
        let store = try OwnReactionMarks(defaults: defaults(), key: "marks")
        for index in 0 ..< OwnReactionMarks.limit {
            store.record(mark(secondsAgo: Double(index + 1)), roomId: "!r\(index)")
        }
        store.record(mark(secondsAgo: 0), roomId: "!new")
        #expect(store.marks.count == OwnReactionMarks.limit)
        #expect(store.marks["!new"] != nil)
        // The oldest mark was the last one written in the loop.
        #expect(store.marks["!r\(OwnReactionMarks.limit - 1)"] == nil)
    }

    @Test
    func removeAllForgetsTheStoredMarks() throws {
        let defaults = try defaults()
        let store = OwnReactionMarks(defaults: defaults, key: "marks")
        store.record(mark(secondsAgo: 0), roomId: "!a")
        store.removeAll()
        #expect(OwnReactionMarks(defaults: defaults, key: "marks").marks.isEmpty)
    }

    // MARK: Draft cache

    @Test
    func composerReportsKeepTheCacheCurrent() {
        let model = ChatListDraftsModel()
        model.roomDraftDidChange(
            roomId: "!a",
            draft: ComposerDraft(plainText: "Later", htmlText: nil, draftType: .newMessage, attachments: [])
        )
        #expect(model.drafts.rooms == ["!a": "Later"])

        // An edit is not a draft on the row.
        model.roomDraftDidChange(
            roomId: "!a",
            draft: ComposerDraft(plainText: "Fix", htmlText: nil, draftType: .edit(eventId: "$e"), attachments: [])
        )
        #expect(model.drafts.rooms.isEmpty)

        model.roomDraftDidChange(
            roomId: "!b",
            draft: ComposerDraft(plainText: "Yes", htmlText: nil, draftType: .reply(eventId: "$r"), attachments: [])
        )
        model.roomDraftDidChange(roomId: "!b", draft: nil)
        #expect(model.drafts.rooms.isEmpty)
    }

    @Test
    func mergedDraftClearsWithAnEmptyText() {
        let model = ChatListDraftsModel()
        model.mergedDraftDidChange(mergeId: "m-seth", text: "Hey")
        #expect(model.drafts.merges == ["m-seth": "Hey"])
        model.mergedDraftDidChange(mergeId: "m-seth", text: "")
        #expect(model.drafts.merges.isEmpty)
    }

    // MARK: SDK filter mapping

    @Test
    func draftsWithoutANarrowingShowsNoChat() {
        guard case let .any(filters) = ChatListFilter.drafts.roomListFilter(labelRooms: nil),
              case let .all(chats) = filters.last
        else {
            Issue.record("unexpected filter shape")
            return
        }
        #expect(chats.count == 2)
        guard case let .identifiers(identifiers) = chats.last else {
            Issue.record("no narrowing")
            return
        }
        #expect(identifiers.isEmpty)
    }

    @Test
    func unansweredKeepsTheInboxFilter() {
        guard case let .any(filters) = ChatListFilter.unanswered.roomListFilter(labelRooms: nil),
              case let .all(chats) = filters.last
        else {
            Issue.record("unexpected filter shape")
            return
        }
        #expect(chats.count == 1)
        guard case .nonLowPriority = chats.first else {
            Issue.record("not the Inbox filter")
            return
        }
    }
}
