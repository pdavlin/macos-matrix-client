import Foundation
import Models
import Testing

/// MATRIX-208: the bookmarks account data and its rules.
struct BookmarkDocumentTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let a = BookmarkKey(roomId: "!a:davlin.io", eventId: "$1")
    private static let b = BookmarkKey(roomId: "!b:davlin.io", eventId: "$2")
    private static let c = BookmarkKey(roomId: "!a:davlin.io", eventId: "$3")

    private func document(_ entries: [(BookmarkKey, TimeInterval)]) -> BookmarkDocument {
        var document = BookmarkDocument()
        for (key, offset) in entries {
            document.setBookmarked(key, true, savedAt: Self.t0.addingTimeInterval(offset))
        }
        return document
    }

    private func object(_ json: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
    }

    // MARK: - Wire format

    @Test func eventTypeIsInTheAppNamespace() {
        #expect(BookmarkDocument.eventType == "io.davlin.matrixclient.bookmarks")
    }

    @Test func encodesIdsAndMillisecondTimesOnly() throws {
        let json = try document([(Self.a, 0)]).jsonString()
        #expect(json == #"{"bookmarks":[{"event_id":"$1","room_id":"!a:davlin.io","saved_at":1800000000000}],"version":1}"#)
        // No message text: an entry has exactly the three keys.
        let entries = try #require(object(json)["bookmarks"] as? [[String: Any]])
        #expect(entries.map { Set($0.keys) } == [["room_id", "event_id", "saved_at"]])
    }

    @Test func roundTripsThroughJSON() throws {
        let original = document([(Self.a, 0), (Self.b, 60.5)])
        let read = try BookmarkDocument.read(original.jsonString())
        #expect(read == .parsed(original))
    }

    @Test func savedTimeIsRoundedToMilliseconds() throws {
        // The written document must equal its echo, or the echo gate holds
        // reads back until its timeout.
        var document = BookmarkDocument()
        document.setBookmarked(Self.a, true, savedAt: Self.t0.addingTimeInterval(0.123_456_7))
        #expect(try BookmarkDocument.read(document.jsonString()) == .parsed(document))
    }

    @Test func keepsUnknownFields() throws {
        let json = #"{"version":1,"color":"red","bookmarks":[{"room_id":"!a","event_id":"$1","saved_at":5,"note":{"x":1}}]}"#
        guard case var .parsed(document) = BookmarkDocument.read(json) else {
            Issue.record("did not parse")
            return
        }
        document.setBookmarked(Self.b, true, savedAt: Self.t0)
        let written = try object(document.jsonString())
        #expect(written["color"] as? String == "red")
        let entries = try #require(written["bookmarks"] as? [[String: Any]])
        #expect(entries.first?["note"] as? [String: Int] == ["x": 1])
        #expect(entries.count == 2)
    }

    @Test func missingFieldsReadAsDefaults() {
        #expect(BookmarkDocument.read("{}") == .parsed(BookmarkDocument()))
        #expect(BookmarkDocument.read(nil) == .empty)
        #expect(BookmarkDocument.read(nil).writableBase == BookmarkDocument())
    }

    @Test func malformedEntryMakesTheEventUnreadableAndReadOnly() {
        let result = BookmarkDocument.read(#"{"bookmarks":[{"room_id":"!a"}]}"#)
        guard case .unreadable = result else {
            Issue.record("expected unreadable, got \(result)")
            return
        }
        #expect(result.document == BookmarkDocument())
        #expect(result.writableBase == nil)
    }

    @Test func newerVersionIsShownButNotWritable() {
        let result = BookmarkDocument.read(#"{"version":2,"bookmarks":[{"room_id":"!a","event_id":"$1","saved_at":1}]}"#)
        #expect(result.document.bookmarks.count == 1)
        #expect(result.writableBase == nil)
    }

    @Test func duplicateEntriesKeepTheFirst() {
        let json = #"{"bookmarks":[{"room_id":"!a","event_id":"$1","saved_at":1},{"room_id":"!a","event_id":"$1","saved_at":9}]}"#
        let document = BookmarkDocument.read(json).document
        #expect(document.bookmarks.map(\.savedAt) == [Date(timeIntervalSince1970: 0.001)])
    }

    // MARK: - Changes

    @Test func setBookmarkedIsIdempotent() {
        var document = document([(Self.a, 0)])
        let before = document
        document.setBookmarked(Self.a, true, savedAt: Self.t0.addingTimeInterval(99))
        #expect(document == before)
        document.setBookmarked(Self.b, false)
        #expect(document == before)
    }

    @Test func removeTakesOnlyThatMessage() {
        var document = document([(Self.a, 0), (Self.c, 1)])
        document.setBookmarked(Self.a, false)
        #expect(document.keys == [Self.c])
        #expect(!document.contains(Self.a))
    }

    @Test func sameEventInTwoRoomsIsTwoBookmarks() {
        // A merged chat keeps each bookmark's own member room.
        let other = BookmarkKey(roomId: "!b:davlin.io", eventId: "$1")
        #expect(document([(Self.a, 0), (other, 1)]).bookmarks.count == 2)
    }

    @Test func listIsNewestSavedFirst() {
        let document = document([(Self.a, 10), (Self.b, 30), (Self.c, 20)])
        #expect(document.newestFirst.map(\.key) == [Self.b, Self.c, Self.a])
    }

    @Test func equalTimesListTheLaterStoredFirst() {
        let document = document([(Self.a, 0), (Self.b, 0)])
        #expect(document.newestFirst.map(\.key) == [Self.b, Self.a])
    }

    // MARK: - Echo gate

    @Test func echoGateHoldsTheWriteUntilItsEcho() {
        var gate = AccountDataEchoGate<BookmarkDocument>(timeout: 30)
        let written = document([(Self.a, 0)])
        gate.didWrite(written, now: Self.t0)
        let r1 = gate.pendingDocument(now: Self.t0) == written
        #expect(r1)
        let r2 = gate.accept(BookmarkDocument(), now: Self.t0.addingTimeInterval(1))
        #expect(!r2)
        let r3 = gate.accept(written, now: Self.t0.addingTimeInterval(2))
        #expect(r3)
        let r4 = gate.pendingDocument(now: Self.t0.addingTimeInterval(3)) == nil
        #expect(r4)
    }

    @Test func echoGateGivesUpAfterTheTimeout() {
        var gate = AccountDataEchoGate<BookmarkDocument>(timeout: 30)
        gate.didWrite(document([(Self.a, 0)]), now: Self.t0)
        let r5 = gate.accept(nil, now: Self.t0.addingTimeInterval(31))
        #expect(r5)
        let r6 = gate.accept(nil, now: Self.t0.addingTimeInterval(32))
        #expect(r6)
    }

    @Test func echoGateWithoutAWriteAcceptsEveryRead() {
        var gate = AccountDataEchoGate<BookmarkDocument>()
        let r7 = gate.accept(nil)
        #expect(r7)
        let r8 = gate.pendingDocument() == nil
        #expect(r8)
    }
}

/// MATRIX-208: the Bookmarks list rows.
struct BookmarkListRowTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func rowsFollowTheListOrderAndTheReadState() {
        var document = BookmarkDocument()
        let a = BookmarkKey(roomId: "!a", eventId: "$1")
        let b = BookmarkKey(roomId: "!b", eventId: "$2")
        let c = BookmarkKey(roomId: "!gone", eventId: "$3")
        document.setBookmarked(a, true, savedAt: Self.t0)
        document.setBookmarked(b, true, savedAt: Self.t0.addingTimeInterval(1))
        document.setBookmarked(c, true, savedAt: Self.t0.addingTimeInterval(2))
        let roomA = BookmarkListRow.Room(title: "Alpha", avatarUrl: nil, initials: .room(title: "Alpha", roomId: "!a"))
        let message = BookmarkListRow.Message(senderName: "Seth", preview: "hi", date: Self.t0)

        let rows = BookmarkListRow.rows(
            for: document,
            rooms: ["!a": roomA, "!b": roomA],
            messages: [a: message, c: nil]
        )
        #expect(rows.map(\.id) == [c, b, a])
        #expect(rows.map(\.content) == [.unavailable, .loading, .message(message)])
        #expect(rows[0].room == .unknown(roomId: "!gone"))
        #expect(rows[2].room.title == "Alpha")
    }

    @Test func previewUsesTheChatListWordingWithoutAPrefix() {
        #expect(BookmarkListRow.preview(of: .text("line one\nline two"), senderId: "@s:x", senderName: "Seth") == "line one line two")
        #expect(BookmarkListRow.preview(of: .image, senderId: "@s:x", senderName: "Seth") == "Photo")
        #expect(BookmarkListRow.preview(of: .other, senderId: "@s:x", senderName: "Seth") == "")
    }
}
