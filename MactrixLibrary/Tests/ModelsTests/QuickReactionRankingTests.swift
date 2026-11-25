import Foundation
import Models
import Testing

/// MATRIX-262: the quick reactions of a room.
struct QuickReactionRankingTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let custom = "mxc://davlin.io/partyparrot"

    private static func at(_ seconds: TimeInterval) -> Date {
        t0.addingTimeInterval(seconds)
    }

    /// One row of a test document: a key's count and last use in a room.
    private struct Row {
        let roomId: String
        let key: String
        let count: Int
        /// Seconds after `t0`.
        let seconds: TimeInterval

        init(_ roomId: String, _ key: String, _ count: Int, _ seconds: TimeInterval) {
            self.roomId = roomId
            self.key = key
            self.count = count
            self.seconds = seconds
        }
    }

    private static func usage(_ rows: [Row]) -> ReactionUsageDocument {
        var rooms: [String: [String: ReactionUse]] = [:]
        for row in rows {
            rooms[row.roomId, default: [:]][row.key] = ReactionUse(count: row.count, lastUsedAt: at(row.seconds))
        }
        return ReactionUsageDocument(rooms: rooms.mapValues { RoomReactionUsage(reactions: $0) })
    }

    private static func keys(
        _ roomId: String = "!a",
        usage: ReactionUsageDocument = ReactionUsageDocument(),
        spaces: RoomSpaceMap = RoomSpaceMap(),
        labels: ChatLabelDocument = ChatLabelDocument(),
        recents: [String] = []
    ) -> [String] {
        QuickReactionRanking.keys(forRoom: roomId, usage: usage, spaces: spaces, labels: labels, recents: recents)
    }

    // MARK: Step 1, the room

    @Test func theRoomsMostUsedReactionsComeFirst() {
        let usage = Self.usage([Row("!a", "👍", 1, 50), Row("!a", "😂", 5, 1), Row("!a", "🔥", 3, 2), Row("!a", "👀", 2, 40)])
        #expect(Self.keys(usage: usage, recents: ["🙏"]) == ["😂", "🔥", "👀"])
    }

    @Test func aTieGoesToTheMostRecentUse() {
        let usage = Self.usage([Row("!a", "😂", 2, 1), Row("!a", "🔥", 2, 3), Row("!a", "👀", 2, 2), Row("!a", "🙏", 2, 0)])
        #expect(Self.keys(usage: usage) == ["🔥", "👀", "😂"])
    }

    @Test func anotherRoomsUseDoesNotRankThisRoom() {
        let usage = Self.usage([Row("!a", "😂", 1, 1), Row("!b", "🔥", 9, 2)])
        #expect(Self.keys(usage: usage, recents: ["🙏"]) == ["😂", "🙏", "👍"])
    }

    // MARK: Step 2, the space or label

    @Test func theSpaceFillsTheRestMostRecentFirst() {
        let spaces = RoomSpaceMap(parents: ["!a": ["!space"], "!b": ["!space"], "!c": ["!space"], "!d": ["!other"]])
        let usage = Self.usage([
            Row("!a", "😂", 4, 1),
            Row("!b", "👀", 9, 2),
            Row("!c", "🔥", 1, 5),
            Row("!d", "🙏", 1, 9),
        ])
        #expect(Self.keys(usage: usage, spaces: spaces, recents: ["🎉"]) == ["😂", "🔥", "👀"])
    }

    @Test func theLabelFillsTheRest() {
        let labels = ChatLabelDocument(labels: [ChatLabel(name: "Work", rooms: ["!a", "!e"])])
        let usage = Self.usage([Row("!a", "😂", 1, 1), Row("!e", "🔥", 1, 2), Row("!f", "🙏", 1, 9)])
        #expect(Self.keys(usage: usage, labels: labels) == ["😂", "🔥", "👍"])
    }

    @Test func aRoomInSeveralTakesTheUnionMostRecentFirst() {
        let spaces = RoomSpaceMap(parents: ["!a": ["!space"], "!b": ["!space"]])
        let labels = ChatLabelDocument(labels: [
            ChatLabel(name: "Work", rooms: ["!a", "!e"]),
            ChatLabel(name: "Friends", rooms: ["!g", "!a"]),
        ])
        let usage = Self.usage([Row("!b", "👀", 1, 2), Row("!e", "🔥", 1, 5), Row("!g", "🙏", 1, 3)])
        #expect(Self.keys(usage: usage, spaces: spaces, labels: labels) == ["🔥", "🙏", "👀"])
    }

    @Test func aSubSpaceCountsAsItsRailSpace() {
        // "!a" and "!b" are in two sub-spaces of the rail space "!top".
        let spaces = RoomSpaceMap(parents: ["!a": ["!sub1"], "!b": ["!sub2"], "!sub1": ["!top"], "!sub2": ["!top"]])
        let usage = Self.usage([Row("!b", "🔥", 1, 2)])
        #expect(Self.keys(usage: usage, spaces: spaces) == ["🔥", "👍", "🎉"])
    }

    @Test func aRoomInNoSpaceOrLabelSkipsTheFill() {
        let spaces = RoomSpaceMap(parents: ["!b": ["!space"], "!c": ["!space"]])
        let usage = Self.usage([Row("!b", "🔥", 1, 2), Row("!c", "👀", 1, 3)])
        #expect(Self.keys(usage: usage, spaces: spaces, recents: ["🙏"]) == ["🙏", "👍", "🎉"])
    }

    // MARK: Steps 3 and 4

    @Test func theRecentsFillWhatTheRoomAndItsSpaceLeave() {
        let usage = Self.usage([Row("!a", "😂", 1, 1)])
        #expect(Self.keys(usage: usage, recents: ["🙏", "😂", "🎉"]) == ["😂", "🙏", "🎉"])
    }

    @Test func withNoUseTheRecentsThenTheDefaultsShow() {
        #expect(Self.keys() == MessageActionModel.defaultQuickReactionKeys)
        #expect(Self.keys(recents: ["🙏"]) == ["🙏", "👍", "🎉"])
    }

    @Test func noKeyShowsTwice() {
        let spaces = RoomSpaceMap(parents: ["!a": ["!space"], "!b": ["!space"]])
        let usage = Self.usage([Row("!a", "👍", 2, 1), Row("!b", "👍", 5, 9), Row("!b", "🎉", 1, 2)])
        let keys = Self.keys(usage: usage, spaces: spaces, recents: ["🎉", "👍"])
        #expect(keys == ["👍", "🎉", "❤️"])
    }

    @Test func theCountIsTheHoverRowCount() {
        let usage = Self.usage((0 ..< 10).map { Row("!a", "\($0)", $0 + 1, 0) })
        #expect(Self.keys(usage: usage).count == MessageActionModel.quickReactionCount)
    }

    // MARK: Custom emoji

    @Test func aCustomEmojiUsedInTheRoomShows() {
        let usage = Self.usage([Row("!a", Self.custom, 3, 1), Row("!a", "😂", 1, 2)])
        #expect(Self.keys(usage: usage) == [Self.custom, "😂", "👍"])
    }

    @Test func aCustomEmojiOfTheSameWorkspaceSpaceFills() {
        let spaces = RoomSpaceMap(parents: ["!a": ["!slack"], "!b": ["!slack"]])
        let usage = Self.usage([Row("!b", Self.custom, 1, 2)])
        #expect(Self.keys(usage: usage, spaces: spaces) == [Self.custom, "👍", "🎉"])
    }

    @Test func aCustomEmojiOfAnotherWorkspaceDoesNotFill() {
        // "!b" shares the rail space "!top" and a label with "!a", but its
        // workspace space is another one.
        let spaces = RoomSpaceMap(parents: ["!a": ["!slackA"], "!b": ["!slackB"], "!slackA": ["!top"], "!slackB": ["!top"]])
        let labels = ChatLabelDocument(labels: [ChatLabel(name: "Work", rooms: ["!a", "!b", "!c"])])
        let usage = Self.usage([Row("!b", Self.custom, 5, 9), Row("!b", "🔥", 1, 1), Row("!c", "mxc://davlin.io/other", 1, 8)])
        #expect(Self.keys(usage: usage, spaces: spaces, labels: labels) == ["🔥", "👍", "🎉"])
    }

    @Test func aCustomEmojiInTheRecentsNeverShows() {
        #expect(Self.keys(recents: [Self.custom, "🙏"]) == ["🙏", "👍", "🎉"])
    }
}

/// MATRIX-262: the reaction-use document: counts, caps, and the wire format.
struct ReactionUsageDocumentTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func aUseCountsUpAndMovesTheLastUse() {
        var document = ReactionUsageDocument()
        document.record("👍", inRoom: "!a", at: Self.t0)
        document.record("👍", inRoom: "!a", at: Self.t0.addingTimeInterval(5))
        // A use with an earlier time, such as a replay, keeps the later time.
        document.record("👍", inRoom: "!a", at: Self.t0.addingTimeInterval(1))
        let use = document.rooms["!a"]?.reactions["👍"]
        #expect(use == ReactionUse(count: 3, lastUsedAt: Self.t0.addingTimeInterval(5)))
    }

    @Test func anEmptyKeyOrRoomRecordsNothing() {
        var document = ReactionUsageDocument()
        document.record("", inRoom: "!a", at: Self.t0)
        document.record("👍", inRoom: "", at: Self.t0)
        #expect(document.rooms.isEmpty)
    }

    @Test func aRoomKeepsAtMostTheCapAndDropsTheLeastUsed() {
        var document = ReactionUsageDocument()
        let cap = ReactionUsageDocument.maxReactionsPerRoom
        for index in 0 ..< cap {
            // Every key twice, apart from "k0", which is the least used.
            document.record("k\(index)", inRoom: "!a", at: Self.t0.addingTimeInterval(Double(index)))
            if index > 0 {
                document.record("k\(index)", inRoom: "!a", at: Self.t0.addingTimeInterval(Double(index)))
            }
        }
        document.record("new", inRoom: "!a", at: Self.t0.addingTimeInterval(100))
        let reactions = document.rooms["!a"]?.reactions ?? [:]
        #expect(reactions.count == cap)
        #expect(reactions["new"]?.count == 1)
        #expect(reactions["k0"] == nil)
    }

    @Test func atTheCapATieDropsTheOldestUse() {
        var document = ReactionUsageDocument()
        let cap = ReactionUsageDocument.maxReactionsPerRoom
        for index in 0 ..< cap {
            document.record("k\(index)", inRoom: "!a", at: Self.t0.addingTimeInterval(Double(index)))
        }
        document.record("new", inRoom: "!a", at: Self.t0.addingTimeInterval(100))
        let reactions = document.rooms["!a"]?.reactions ?? [:]
        #expect(reactions.count == cap)
        #expect(reactions["k0"] == nil)
        #expect(reactions["k1"] != nil)
        #expect(reactions["new"] != nil)
    }

    @Test func theDocumentKeepsAtMostTheRoomCapAndDropsTheLeastRecent() {
        var document = ReactionUsageDocument()
        let cap = ReactionUsageDocument.maxRooms
        for index in 0 ..< cap {
            // "!r0" has the oldest use, though it is the most used.
            document.record("👍", inRoom: "!r\(index)", at: Self.t0.addingTimeInterval(Double(index)))
        }
        document.record("👍", inRoom: "!r0", at: Self.t0.addingTimeInterval(-10))
        document.record("👍", inRoom: "!new", at: Self.t0.addingTimeInterval(-20))
        #expect(document.rooms.count == cap)
        #expect(document.rooms["!new"] != nil)
        #expect(document.rooms["!r0"] == nil)
        #expect(document.rooms["!r1"] != nil)
    }

    @Test func theWireFormatRoundTripsAndKeepsUnknownFields() throws {
        let json = """
        {"future": true, "version": 1, "rooms": {"!a:davlin.io": {"pinned": ["👍"], "reactions": {
          "👍": {"count": 4, "last_used_at": 1800000000123},
          "mxc://davlin.io/abc": {"count": 1, "last_used_at": 1800000000000}}}}}
        """
        guard case let .parsed(document) = ReactionUsageDocument.read(json) else {
            Issue.record("the document did not parse")
            return
        }
        let room = document.rooms["!a:davlin.io"]
        #expect(room?.reactions["👍"]?.count == 4)
        #expect(room?.reactions["mxc://davlin.io/abc"]?.count == 1)

        let written = try document.jsonString()
        #expect(written.contains("\"future\":true"))
        #expect(written.contains("\"pinned\":[\"👍\"]"))
        #expect(written.contains("\"last_used_at\":1800000000123"))
        let reread = ReactionUsageDocument.read(written)
        #expect(reread == .parsed(document))
    }

    @Test func aRecordedTimeEqualsItselfAfterARoundTrip() throws {
        var document = ReactionUsageDocument()
        document.record("👍", inRoom: "!a", at: Date(timeIntervalSince1970: 1_800_000_000.123_456_7))
        let reread = try ReactionUsageDocument.read(document.jsonString())
        #expect(reread == .parsed(document))
    }

    @Test func aMissingEventIsAnEmptyWritableDocument() {
        let result = ReactionUsageDocument.read(nil)
        #expect(result == .empty)
        #expect(result.writableBase == ReactionUsageDocument())
    }

    @Test func anUnreadableEventIsNotWritable() {
        let result = ReactionUsageDocument.read("{\"rooms\": {\"!a\": {\"reactions\": {\"👍\": {\"count\": 1}}}}}")
        guard case .unreadable = result else {
            Issue.record("a use with no time must not parse")
            return
        }
        #expect(result.writableBase == nil)
        #expect(result.document.rooms.isEmpty)
    }

    @Test func aNewerVersionIsReadButNotWritable() {
        let result = ReactionUsageDocument.read("{\"version\": 2, \"rooms\": {}}")
        #expect(result.document.version == 2)
        #expect(result.writableBase == nil)
    }
}
