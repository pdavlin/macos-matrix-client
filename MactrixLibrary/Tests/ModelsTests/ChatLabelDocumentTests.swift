import Foundation
@testable import Models
import Testing

/// MATRIX-77: the labels account-data document: parsing, round-trips,
/// mutations, and the Inbox and mute rules.
struct ChatLabelDocumentTests {
    private static let sample = """
    {"version":1,"labels":[
      {"id":"work","name":"Work","colorIndex":3,"icon":"briefcase","muted":false,"inboxVisibility":"all","rooms":["!a:x","!b:x"]},
      {"id":"fam","name":"Family","colorIndex":null,"icon":null,"muted":true,"inboxVisibility":"hidden","rooms":["!c:x"]}
    ]}
    """

    private func parsed(_ json: String) throws -> ChatLabelDocument {
        guard case let .parsed(document) = ChatLabelDocument.read(json) else {
            Issue.record("expected the document to parse")
            throw CancellationError()
        }
        return document
    }

    // MARK: Reading

    @Test
    func missingEventIsEmptyAndWritable() {
        let result = ChatLabelDocument.read(nil)
        #expect(result == .empty)
        #expect(result.document.labels.isEmpty)
        #expect(result.writableBase == ChatLabelDocument())
    }

    @Test
    func parsesEveryField() throws {
        let document = try parsed(Self.sample)
        #expect(document.version == 1)
        #expect(document.labels.map(\.id) == ["work", "fam"])
        let work = try #require(document.label(id: "work"))
        #expect(work.name == "Work")
        #expect(work.colorIndex == 3)
        #expect(work.icon == "briefcase")
        #expect(!work.isMuted)
        #expect(work.inboxVisibility == .all)
        #expect(work.rooms == ["!a:x", "!b:x"])
        let family = try #require(document.label(id: "fam"))
        #expect(family.colorIndex == nil)
        #expect(family.icon == nil)
        #expect(family.isMuted)
        #expect(family.inboxVisibility == .hidden)
    }

    @Test
    func optionalFieldsDefault() throws {
        let document = try parsed(#"{"version":1,"labels":[{"id":"x","name":"X"}]}"#)
        let label = try #require(document.labels.first)
        #expect(label.colorIndex == nil)
        #expect(label.icon == nil)
        #expect(!label.isMuted)
        #expect(label.inboxVisibility == .all)
        #expect(label.rooms.isEmpty)
    }

    @Test
    func unknownInboxVisibilityShowsTheChats() throws {
        let document = try parsed(#"{"version":1,"labels":[{"id":"x","name":"X","inboxVisibility":"pinned"}]}"#)
        #expect(document.labels.first?.inboxVisibility == .all)
    }

    @Test
    func duplicateRoomsCollapse() throws {
        let document = try parsed(#"{"version":1,"labels":[{"id":"x","name":"X","rooms":["!a","!b","!a"]}]}"#)
        #expect(document.labels.first?.rooms == ["!a", "!b"])
    }

    @Test(arguments: [
        "not json",
        "[]",
        #"{"labels":[]}"#,
        #"{"version":"1","labels":[]}"#,
        #"{"version":1,"labels":[{"name":"No ID"}]}"#,
        #"{"version":1,"labels":[{"id":"x","name":"X","rooms":"!a"}]}"#,
    ])
    func malformedContentIsUnreadableAndNotWritable(json: String) {
        let result = ChatLabelDocument.read(json)
        guard case let .unreadable(raw, _) = result else {
            Issue.record("expected unreadable, got \(result)")
            return
        }
        #expect(raw == json)
        #expect(result.document.labels.isEmpty)
        #expect(result.writableBase == nil)
    }

    @Test
    func newerVersionIsReadButNotWritable() throws {
        let result = ChatLabelDocument.read(#"{"version":2,"labels":[{"id":"x","name":"X"}]}"#)
        #expect(result.document.labels.count == 1)
        #expect(!result.document.isWritable)
        #expect(result.writableBase == nil)
    }

    // MARK: Round-trip

    @Test
    func roundTripKeepsEveryField() throws {
        let document = try parsed(Self.sample)
        let again = try parsed(document.jsonString())
        #expect(again == document)
    }

    @Test
    func roundTripKeepsUnknownFields() throws {
        let json = """
        {"version":1,"theme":{"compact":true,"ratio":0.5},"labels":[
          {"id":"x","name":"X","emoji":"🚀","order":7,"tags":["a",null,false]}
        ]}
        """
        var document = try parsed(json)
        document.rename("x", to: "Renamed")
        let written = try document.jsonString()
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(written.utf8)) as? [String: Any]
        )
        let theme = try #require(object["theme"] as? [String: Any])
        #expect(theme["compact"] as? Bool == true)
        #expect(theme["ratio"] as? Double == 0.5)
        let label = try #require((object["labels"] as? [[String: Any]])?.first)
        #expect(label["name"] as? String == "Renamed")
        #expect(label["emoji"] as? String == "🚀")
        #expect(label["order"] as? Int == 7)
        #expect((label["tags"] as? [Any])?.count == 3)
        #expect(try parsed(written) == document)
    }

    @Test
    func writesExplicitNullsAndTheEventShape() throws {
        var document = ChatLabelDocument()
        document.create(id: "x", name: "X", rooms: ["!a"])
        let written = try document.jsonString()
        #expect(written == """
        {"labels":[{"colorIndex":null,"icon":null,"id":"x","inboxVisibility":"all","muted":false,"name":"X","rooms":["!a"]}],"version":1}
        """)
    }

    // MARK: Mutations

    @Test
    func createAppendsAtTheEnd() {
        var document = ChatLabelDocument()
        document.create(id: "a", name: "A")
        let created = document.create(id: "b", name: "B", colorIndex: 2, icon: "star", rooms: ["!r", "!r"])
        #expect(document.labels.map(\.id) == ["a", "b"])
        #expect(created.rooms == ["!r"])
        #expect(document.label(id: "b") == created)
    }

    @Test
    func editsByID() {
        var document = ChatLabelDocument()
        document.create(id: "a", name: "A")
        document.rename("a", to: "Alpha")
        document.setColor("a", colorIndex: 5)
        document.setIcon("a", icon: "leaf")
        document.setMuted("a", true)
        document.setInboxVisibility("a", .hidden)
        let label = document.label(id: "a")
        #expect(label?.name == "Alpha")
        #expect(label?.colorIndex == 5)
        #expect(label?.icon == "leaf")
        #expect(label?.isMuted == true)
        #expect(label?.isShownInInbox == false)
        document.toggleMuted("a")
        #expect(document.label(id: "a")?.isMuted == false)
    }

    @Test
    func mutatingAMissingLabelIsANoOp() {
        var document = ChatLabelDocument()
        document.create(id: "a", name: "A")
        let before = document
        document.rename("gone", to: "X")
        document.addRoom("!r", to: "gone")
        document.toggleMuted("gone")
        document.move("gone", to: 0)
        document.delete("gone")
        #expect(document == before)
    }

    @Test
    func roomMembership() {
        var document = ChatLabelDocument()
        document.create(id: "a", name: "A")
        document.addRoom("!1", to: "a")
        document.addRoom("!2", to: "a")
        document.addRoom("!1", to: "a")
        #expect(document.label(id: "a")?.rooms == ["!1", "!2"])
        document.removeRoom("!1", from: "a")
        #expect(document.label(id: "a")?.rooms == ["!2"])
        document.toggleRoom("!3", in: "a")
        #expect(document.label(id: "a")?.rooms == ["!2", "!3"])
        document.toggleRoom("!2", in: "a")
        #expect(document.label(id: "a")?.rooms == ["!3"])
        document.setRooms(["!4", "!5", "!4"], for: "a")
        #expect(document.label(id: "a")?.rooms == ["!4", "!5"])
    }

    @Test
    func applyDraftKeepsUnknownFields() throws {
        var document = try parsed(#"{"version":1,"labels":[{"id":"x","name":"X","extra":1}]}"#)
        document.apply(ChatLabelDraft(name: "  New  ", colorIndex: 1, icon: "tag", rooms: ["!a"]), to: "x")
        let label = try #require(document.label(id: "x"))
        #expect(label.name == "New")
        #expect(label.colorIndex == 1)
        #expect(label.icon == "tag")
        #expect(label.rooms == ["!a"])
        #expect(label.unknownFields == ["extra": .integer(1)])
    }

    @Test
    func deleteAndMove() {
        var document = ChatLabelDocument()
        for id in ["a", "b", "c", "d"] {
            document.create(id: id, name: id)
        }
        document.move("d", to: 0)
        #expect(document.labels.map(\.id) == ["d", "a", "b", "c"])
        document.move("d", to: 99)
        #expect(document.labels.map(\.id) == ["a", "b", "c", "d"])
        document.move("a", to: -3)
        #expect(document.labels.map(\.id) == ["a", "b", "c", "d"])
        document.move("a", to: 2)
        #expect(document.labels.map(\.id) == ["b", "c", "a", "d"])
        document.delete("c")
        #expect(document.labels.map(\.id) == ["b", "a", "d"])
    }

    // MARK: Queries

    private var rules: ChatLabelDocument {
        ChatLabelDocument(labels: [
            ChatLabel(id: "work", name: "Work", isMuted: true, rooms: ["!shared", "!work"]),
            ChatLabel(id: "news", name: "News", isMuted: true, inboxVisibility: .hidden, rooms: ["!shared", "!news"]),
            ChatLabel(id: "fam", name: "Family", rooms: ["!fam", "!both"]),
            ChatLabel(id: "loud", name: "Loud", isMuted: true, rooms: ["!both"]),
        ])
    }

    @Test
    func labelsContainingARoomFollowRailOrder() {
        #expect(rules.labels(containing: "!shared").map(\.id) == ["work", "news"])
        #expect(rules.labels(containing: "!nowhere").isEmpty)
        #expect(rules.labelledRoomIds == ["!shared", "!work", "!news", "!fam", "!both"])
    }

    @Test
    func anyHiddenLabelHidesTheRoomFromTheInbox() {
        // "!shared" is also in "work", which shows in the Inbox: hidden wins.
        #expect(rules.inboxHiddenRoomIds == ["!shared", "!news"])
    }

    @Test
    func roomIsMutedByLabelsOnlyWhenEveryLabelIsMuted() {
        let document = rules
        #expect(document.labelMutedRoomIds == ["!shared", "!work", "!news"])
        #expect(document.isRoomMutedByLabels("!shared"))
        // "!both" is in muted "loud" and unmuted "fam".
        #expect(!document.isRoomMutedByLabels("!both"))
        #expect(!document.isRoomMutedByLabels("!fam"))
        // No label, no label mute.
        #expect(!document.isRoomMutedByLabels("!nowhere"))
    }

    @Test
    func monogramIsTheFirstLetter() {
        #expect(ChatLabel(name: " work").monogram == "W")
        #expect(ChatLabel(name: "").monogram == "")
    }
}
