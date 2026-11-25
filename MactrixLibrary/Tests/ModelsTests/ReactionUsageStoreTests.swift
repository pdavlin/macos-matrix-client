import Foundation
import Models
import Testing

private struct WriteFailed: Error {}

/// MATRIX-262: the reaction-use store and its write gate.
@MainActor
struct ReactionUsageStoreTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// The account data of one event type. A write does not change what a
    /// read returns until the test delivers the sync echo.
    @MainActor
    private final class FakeAccountData {
        var stored: String?
        var writes: [String] = []
        var reads = 0
        var failsWrites = false
        var reports: [String] = []
        /// When set, each write waits for it before it lands.
        var writeLatch: Latch?
        var writesStarted = 0

        var transport: ReactionUsageStore.Transport {
            ReactionUsageStore.Transport(
                read: { [unowned self] in
                    reads += 1
                    return stored
                },
                write: { [unowned self] content in
                    writesStarted += 1
                    await writeLatch?.wait()
                    if failsWrites {
                        throw WriteFailed()
                    }
                    writes.append(content)
                },
                report: { [unowned self] line in reports.append(line) }
            )
        }

        /// Sync brings the last write back.
        func deliverEcho() {
            stored = writes.last
        }

        func written(_ index: Int) -> ReactionUsageDocument {
            ReactionUsageDocument.read(writes[index]).document
        }
    }

    /// Holds the store's write wait until the test opens it.
    @MainActor
    private final class Latch {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters {
                waiter.resume()
            }
            waiters = []
        }
    }

    private static func count(_ document: ReactionUsageDocument, _ key: String, in roomId: String = "!a") -> Int? {
        document.rooms[roomId]?.reactions[key]?.count
    }

    @Test func aBurstOfUsesMakesOneWrite() async {
        let data = FakeAccountData()
        let latch = Latch()
        let store = ReactionUsageStore(transport: data.transport, wait: { await latch.wait() })
        store.record("👍", inRoom: "!a", at: Self.t0)
        store.record("🎉", inRoom: "!a", at: Self.t0.addingTimeInterval(1))
        store.record("👍", inRoom: "!b", at: Self.t0.addingTimeInterval(2))
        #expect(data.writes.isEmpty)
        latch.open()
        await store.waitForWrites()
        #expect(data.writes.count == 1)
        let written = data.written(0)
        #expect(Self.count(written, "👍") == 1)
        #expect(Self.count(written, "🎉") == 1)
        #expect(Self.count(written, "👍", in: "!b") == 1)
    }

    @Test func aUseShowsBeforeItsWrite() {
        let data = FakeAccountData()
        let store = ReactionUsageStore(transport: data.transport, wait: { await Latch().wait() })
        store.record("👍", inRoom: "!a", at: Self.t0)
        #expect(Self.count(store.document, "👍") == 1)
        #expect(data.writes.isEmpty)
    }

    @Test func aRemovedReactionIsNotAUse() async {
        let data = FakeAccountData()
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        store.recordToggle(of: "👍", inRoom: "!a", wasAdded: true, at: Self.t0)
        store.recordToggle(of: "👍", inRoom: "!a", wasAdded: false, at: Self.t0.addingTimeInterval(1))
        store.recordToggle(of: "🔥", inRoom: "!a", wasAdded: false, at: Self.t0.addingTimeInterval(2))
        await store.waitForWrites()
        #expect(Self.count(store.document, "👍") == 1)
        #expect(Self.count(store.document, "🔥") == nil)
        #expect(data.writes.count == 1)
    }

    @Test func aReadBeforeTheEchoKeepsTheWrittenDocument() async {
        let data = FakeAccountData()
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        store.record("👍", inRoom: "!a", at: Self.t0)
        await store.waitForWrites()

        // The store still holds no event: the echo has not come back.
        await store.refresh()
        #expect(Self.count(store.document, "👍") == 1)

        // A second burst starts from the written document, not the old store.
        store.record("👍", inRoom: "!a", at: Self.t0.addingTimeInterval(5))
        await store.waitForWrites()
        #expect(data.writes.count == 2)
        #expect(Self.count(data.written(1), "👍") == 2)
    }

    @Test func afterTheEchoAReadAdoptsAnotherDevicesWrite() async throws {
        let data = FakeAccountData()
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        store.record("👍", inRoom: "!a", at: Self.t0)
        await store.waitForWrites()
        data.deliverEcho()
        await store.refresh()

        // The phone adds a use; the next read shows it.
        var phone = data.written(0)
        phone.record("🔥", inRoom: "!a", at: Self.t0.addingTimeInterval(9))
        data.stored = try phone.jsonString()
        await store.refresh()
        #expect(store.document == phone)
    }

    @Test func aReadKeepsTheUsesThatAreNotWrittenYet() async throws {
        let data = FakeAccountData()
        var phone = ReactionUsageDocument()
        phone.record("🔥", inRoom: "!a", at: Self.t0)
        data.stored = try phone.jsonString()
        let store = ReactionUsageStore(transport: data.transport, wait: { await Latch().wait() })
        store.record("👍", inRoom: "!a", at: Self.t0.addingTimeInterval(1))
        await store.refresh()
        #expect(Self.count(store.document, "🔥") == 1)
        #expect(Self.count(store.document, "👍") == 1)
    }

    @Test func theWriteStartsFromTheStoredDocument() async throws {
        let data = FakeAccountData()
        var phone = ReactionUsageDocument()
        phone.record("🔥", inRoom: "!a", at: Self.t0)
        data.stored = try phone.jsonString()
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        // No refresh first: the write reads the store itself.
        store.record("👍", inRoom: "!b", at: Self.t0.addingTimeInterval(1))
        await store.waitForWrites()
        #expect(Self.count(data.written(0), "🔥") == 1)
        #expect(Self.count(data.written(0), "👍", in: "!b") == 1)
    }

    @Test func anUnreadableEventRefusesEveryWrite() async {
        let data = FakeAccountData()
        data.stored = "{\"rooms\": 5}"
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        await store.refresh()
        #expect(!store.isEditable)
        store.record("👍", inRoom: "!a", at: Self.t0)
        await store.waitForWrites()
        #expect(data.writes.isEmpty)
        // The use of this session still ranks the quick reactions.
        #expect(Self.count(store.document, "👍") == 1)
        #expect(!data.reports.isEmpty)
    }

    @Test func aNewerVersionRefusesEveryWrite() async {
        let data = FakeAccountData()
        data.stored = "{\"version\": 2, \"rooms\": {}}"
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        store.record("👍", inRoom: "!a", at: Self.t0)
        await store.waitForWrites()
        #expect(data.writes.isEmpty)
        #expect(!store.isEditable)
    }

    @Test func aFailedWriteSendsItsUsesWithTheNextWrite() async {
        let data = FakeAccountData()
        data.failsWrites = true
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        store.record("👍", inRoom: "!a", at: Self.t0)
        await store.waitForWrites()
        #expect(data.writes.isEmpty)
        #expect(Self.count(store.document, "👍") == 1)

        data.failsWrites = false
        store.record("🎉", inRoom: "!a", at: Self.t0.addingTimeInterval(1))
        await store.waitForWrites()
        #expect(data.writes.count == 1)
        #expect(Self.count(data.written(0), "👍") == 1)
        #expect(Self.count(data.written(0), "🎉") == 1)
    }

    @Test func aUseDuringAWriteGoesInTheNextWrite() async {
        let data = FakeAccountData()
        let writeLatch = Latch()
        data.writeLatch = writeLatch
        let store = ReactionUsageStore(transport: data.transport, wait: {})
        store.record("👍", inRoom: "!a", at: Self.t0)
        while data.writesStarted == 0 {
            await Task.yield()
        }
        // The first write is in flight.
        store.record("🎉", inRoom: "!a", at: Self.t0.addingTimeInterval(1))
        writeLatch.open()
        await store.waitForWrites()
        #expect(data.writes.count == 2)
        #expect(Self.count(data.written(0), "🎉") == nil)
        #expect(Self.count(data.written(1), "🎉") == 1)
        #expect(Self.count(data.written(1), "👍") == 1)
    }
}
