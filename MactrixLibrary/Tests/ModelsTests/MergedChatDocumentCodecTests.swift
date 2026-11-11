import Foundation
@testable import Models
import Testing

/// MATRIX-140: the merged-chats account-data codec: parsing, unknown-field
/// round-trips, version handling, and the read result.
struct MergedChatDocumentCodecTests {
    private static let sample = """
    {"version":1,"merges":[
      {"id":"seth","name":"Seth","rooms":["!a:x","!b:x"],"default_room":"!a:x","avatar_room":"!b:x"},
      {"id":"ana","name":"Ana","rooms":["!c:x","!d:x","!e:x"]}
    ]}
    """

    private func parsed(_ json: String) throws -> MergedChatStoredDocument {
        guard case let .parsed(stored) = MergedChatDocument.read(json) else {
            Issue.record("expected the document to parse")
            throw CancellationError()
        }
        return stored
    }

    private func object(_ json: String) throws -> [String: Any] {
        let value = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(value as? [String: Any])
    }

    // MARK: Reading

    @Test
    func missingEventIsEmptyAndWritable() {
        let result = MergedChatDocument.read(nil)
        #expect(result == .empty)
        #expect(result.document == MergedChatDocument())
        #expect(result.writableBase == MergedChatStoredDocument())
    }

    @Test
    func parsesEveryField() throws {
        let document = try parsed(Self.sample).document
        #expect(document.version == 1)
        #expect(document.merges.map(\.id) == ["seth", "ana"])
        let seth = try #require(document.merge(id: "seth"))
        #expect(seth.name == "Seth")
        #expect(seth.rooms == ["!a:x", "!b:x"])
        #expect(seth.defaultRoom == "!a:x")
        #expect(seth.avatarRoom == "!b:x")
        let ana = try #require(document.merge(id: "ana"))
        #expect(ana.defaultRoom == nil)
        #expect(ana.avatarRoom == nil)
        #expect(ana.effectiveDefaultRoom == "!c:x")
    }

    @Test
    func nullOptionalRoomsReadAsNil() throws {
        let json = #"{"version":1,"merges":[{"id":"m","name":"M","rooms":["!a","!b"],"default_room":null,"avatar_room":null}]}"#
        let document = try parsed(json).document
        let merge = try #require(document.merges.first)
        #expect(merge.defaultRoom == nil)
        #expect(merge.avatarRoom == nil)
    }

    @Test
    func missingVersionAndMergesDefault() throws {
        #expect(try parsed(#"{"merges":[]}"#).document.version == MergedChatDocument.currentVersion)
        #expect(try parsed("{}").document == MergedChatDocument())
    }

    @Test
    func repeatedRoomsInAMergeAreDropped() throws {
        let document = try parsed(#"{"version":1,"merges":[{"id":"m","name":"M","rooms":["!a","!b","!a"]}]}"#).document
        #expect(document.merges.first?.rooms == ["!a", "!b"])
    }

    @Test
    func malformedContentIsUnreadableAndNotWritable() {
        let inputs = [
            "not json",
            "[]",
            #"{"version":"one","merges":[]}"#,
            #"{"version":1,"merges":{}}"#,
            #"{"version":1,"merges":[{"name":"M","rooms":["!a","!b"]}]}"#,
            #"{"version":1,"merges":[{"id":"m","rooms":["!a","!b"]}]}"#,
            #"{"version":1,"merges":[{"id":"m","name":"M"}]}"#,
            #"{"version":1,"merges":[{"id":"m","name":"M","rooms":"!a"}]}"#,
        ]
        for input in inputs {
            let result = MergedChatDocument.read(input)
            guard case let .unreadable(raw, _) = result else {
                Issue.record("expected \(input) to be unreadable")
                continue
            }
            #expect(raw == input)
            #expect(result.document == MergedChatDocument())
            #expect(result.writableBase == nil)
        }
    }

    @Test
    func repeatedMergeIdIsUnreadable() {
        let json = #"{"version":1,"merges":[{"id":"m","name":"A","rooms":["!a","!b"]},{"id":"m","name":"B","rooms":["!c","!d"]}]}"#
        guard case .unreadable = MergedChatDocument.read(json) else {
            Issue.record("expected a repeated merge ID to be unreadable")
            return
        }
    }

    @Test
    func newerVersionIsReadButNotWritable() {
        let json = #"{"version":2,"merges":[{"id":"m","name":"M","rooms":["!a","!b"],"weight":3}]}"#
        let result = MergedChatDocument.read(json)
        #expect(result.document.version == 2)
        #expect(result.document.merges.map(\.id) == ["m"])
        #expect(!result.document.isWritable)
        #expect(result.writableBase == nil)
    }

    // MARK: Writing

    @Test
    func writesExactKeys() throws {
        var stored = MergedChatStoredDocument()
        stored.update { $0.create(name: "Seth", rooms: ["!a", "!b"], defaultRoom: "!a", avatarRoom: "!b", id: "seth") }
        let json = try stored.jsonString()
        #expect(json == #"{"merges":[{"avatar_room":"!b","default_room":"!a","id":"seth","name":"Seth","rooms":["!a","!b"]}],"version":1}"#)
    }

    @Test
    func nilOptionalRoomsAreLeftOut() throws {
        var stored = MergedChatStoredDocument()
        stored.update { $0.create(name: "M", rooms: ["!a", "!b"], id: "m") }
        let merge = try #require((object(stored.jsonString())["merges"] as? [[String: Any]])?.first)
        #expect(Set(merge.keys) == ["id", "name", "rooms"])
    }

    @Test
    func roundTripIsLossless() throws {
        let stored = try parsed(Self.sample)
        #expect(try parsed(stored.jsonString()) == stored)
    }

    @Test
    func unknownFieldsSurviveAMutation() throws {
        let json = """
        {"version":1,"future":{"a":[1,2.5,true,null,"s"]},"merges":[
          {"id":"seth","name":"Seth","rooms":["!a","!b"],"pinned":true,"meta":{"k":"v"}},
          {"id":"ana","name":"Ana","rooms":["!c","!d"],"color":7}
        ]}
        """
        var stored = try parsed(json)
        stored.update { $0.rename("seth", to: "Seth K") }
        let written = try object(stored.jsonString())
        let future = try #require(written["future"] as? [String: Any])
        #expect((future["a"] as? [Any])?.count == 5)
        let merges = try #require(written["merges"] as? [[String: Any]])
        #expect(merges[0]["name"] as? String == "Seth K")
        #expect(merges[0]["pinned"] as? Bool == true)
        #expect((merges[0]["meta"] as? [String: String]) == ["k": "v"])
        #expect(merges[1]["color"] as? Int == 7)
        #expect(try parsed(stored.jsonString()) == stored)
    }

    @Test
    func unknownFieldsFollowTheMergeNotItsPosition() throws {
        let json = """
        {"version":1,"merges":[
          {"id":"x","name":"X","rooms":["!a","!b"],"tag":"x"},
          {"id":"y","name":"Y","rooms":["!c","!d"],"tag":"y"}
        ]}
        """
        var stored = try parsed(json)
        stored.update { $0.unmerge("x") }
        let merges = try #require(object(stored.jsonString())["merges"] as? [[String: Any]])
        #expect(merges.count == 1)
        #expect(merges[0]["id"] as? String == "y")
        #expect(merges[0]["tag"] as? String == "y")
    }

    @Test
    func removedMergeTakesItsUnknownFieldsAlong() throws {
        let json = #"{"version":1,"merges":[{"id":"x","name":"X","rooms":["!a","!b"],"tag":"x"}]}"#
        var stored = try parsed(json)
        stored.update { $0.unmerge("x") }
        stored.update { $0.create(name: "X again", rooms: ["!a", "!b"], id: "x") }
        let merge = try #require((object(stored.jsonString())["merges"] as? [[String: Any]])?.first)
        #expect(merge["tag"] == nil)
        // The echo of this write parses to an equal value, so the echo gate
        // releases it.
        #expect(try parsed(stored.jsonString()) == stored)
    }

    @Test
    func updateNormalizesTheDocument() throws {
        let json = #"{"version":1,"merges":[{"id":"x","name":"X","rooms":["!a","!b"]},{"id":"y","name":"Y","rooms":["!b","!c"]}]}"#
        var stored = try parsed(json)
        // A no-op change still restores the invariants: !b stays in x, so y
        // has one room left and goes.
        stored.update { _ in }
        #expect(stored.document.merges.map(\.id) == ["x"])
    }

    @Test
    func equalDocumentsEncodeToTheSameString() throws {
        let first = try parsed(Self.sample)
        let second = try parsed(first.jsonString())
        #expect(try first.jsonString() == second.jsonString())
    }
}
