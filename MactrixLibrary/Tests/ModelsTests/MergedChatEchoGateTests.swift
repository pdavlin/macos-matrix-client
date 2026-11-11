import Foundation
@testable import Models
import Testing

/// MATRIX-140: the echo gate between a merged-chats write and its sync echo.
struct MergedChatEchoGateTests {
    private func stored(_ name: String) -> MergedChatStoredDocument {
        MergedChatStoredDocument(MergedChatDocument(merges: [MergedChat(id: "x", name: name, rooms: ["!a", "!b"])]))
    }

    @Test
    func readsPassThroughWithNoPendingWrite() {
        var gate = MergedChatEchoGate()
        let read = MergedChatReadResult.parsed(stored("A"))
        #expect(gate.accept(read) == read)
        #expect(gate.accept(.empty) == .empty)
        #expect(gate.pendingDocument() == nil)
    }

    @Test
    func staleReadIsHeldUntilTheEchoArrives() {
        let start = Date(timeIntervalSince1970: 1000)
        var gate = MergedChatEchoGate(timeout: 30)
        gate.didWrite(stored("B"), now: start)
        #expect(gate.accept(.parsed(stored("A")), now: start.addingTimeInterval(1)) == nil)
        #expect(gate.accept(.empty, now: start.addingTimeInterval(1)) == nil)
        #expect(gate.pendingDocument(now: start.addingTimeInterval(2)) == stored("B"))
        #expect(gate.accept(.parsed(stored("B")), now: start.addingTimeInterval(3)) == .parsed(stored("B")))
        #expect(gate.pendingDocument(now: start.addingTimeInterval(4)) == nil)
        #expect(gate.accept(.parsed(stored("C")), now: start.addingTimeInterval(5)) == .parsed(stored("C")))
    }

    @Test
    func echoParsedFromTheWrittenJsonReleasesTheGate() throws {
        let start = Date(timeIntervalSince1970: 1000)
        var gate = MergedChatEchoGate(timeout: 30)
        let json = #"{"version":1,"extra":1,"merges":[{"id":"x","name":"X","rooms":["!a","!b"],"tag":"t"}]}"#
        guard case var .parsed(written) = MergedChatDocument.read(json) else {
            Issue.record("expected the document to parse")
            return
        }
        written.update { $0.rename("x", to: "Y") }
        gate.didWrite(written, now: start)
        let echo = try MergedChatDocument.read(written.jsonString())
        #expect(gate.accept(echo, now: start.addingTimeInterval(1)) == echo)
        #expect(gate.pendingDocument(now: start.addingTimeInterval(2)) == nil)
    }

    @Test
    func pendingWriteExpires() {
        let start = Date(timeIntervalSince1970: 1000)
        var gate = MergedChatEchoGate(timeout: 30)
        gate.didWrite(stored("B"), now: start)
        #expect(gate.pendingDocument(now: start.addingTimeInterval(31)) == nil)
        gate.didWrite(stored("B"), now: start)
        #expect(gate.accept(.parsed(stored("C")), now: start.addingTimeInterval(31)) == .parsed(stored("C")))
    }

    @Test
    func laterWriteReplacesThePendingOne() {
        let start = Date(timeIntervalSince1970: 1000)
        var gate = MergedChatEchoGate(timeout: 30)
        gate.didWrite(stored("B"), now: start)
        gate.didWrite(stored("C"), now: start.addingTimeInterval(1))
        // The first write's echo is now stale too.
        #expect(gate.accept(.parsed(stored("B")), now: start.addingTimeInterval(2)) == nil)
        #expect(gate.accept(.parsed(stored("C")), now: start.addingTimeInterval(3)) == .parsed(stored("C")))
    }
}
