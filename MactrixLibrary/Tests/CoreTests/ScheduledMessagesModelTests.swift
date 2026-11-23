@testable import Core
import Foundation
import MatrixRustSDK
import Models
import Testing

/// A fake SDK layer for Send Later: an account data value that a write
/// changes at once (an instant sync echo), and scripted answers for the
/// delayed-event calls.
@MainActor
private final class FakeTransport: ScheduledMessageTransport {
    var registry: String?
    var failsWrites = false
    var nextDelayIds = ["d-new"]
    var scheduleFailure: ScheduledMessageFailure?
    var updateFailures: [String: ScheduledMessageFailure] = [:]

    struct ScheduleCall: Equatable {
        let roomId: String
        let contentJSON: String
        let delayMs: UInt64
    }

    private(set) var scheduled: [ScheduleCall] = []
    private(set) var updates: [(delayId: String, update: ScheduledMessageUpdate)] = []
    private(set) var writeCount = 0

    struct WriteFailed: Error {}

    func readRegistry() async throws -> String? {
        registry
    }

    func writeRegistry(_ json: String) async throws {
        writeCount += 1
        if failsWrites { throw WriteFailed() }
        registry = json
    }

    func scheduleMessage(roomId: String, contentJSON: String, delayMs: UInt64) async throws(ScheduledMessageFailure) -> String {
        if let scheduleFailure { throw scheduleFailure }
        scheduled.append(ScheduleCall(roomId: roomId, contentJSON: contentJSON, delayMs: delayMs))
        return nextDelayIds.isEmpty ? UUID().uuidString : nextDelayIds.removeFirst()
    }

    func updateDelayedEvent(delayId: String, update: ScheduledMessageUpdate) async throws(ScheduledMessageFailure) {
        updates.append((delayId, update))
        if let failure = updateFailures[delayId] { throw failure }
    }

    /// The registry as the server holds it now.
    var stored: ScheduledMessageDocument {
        ScheduledMessageDocument.read(registry).document
    }
}

/// MATRIX-212: `ScheduledMessagesModel` over a fake SDK layer: schedule,
/// send now, cancel, edit, the errors, and the cleanup.
@MainActor
struct ScheduledMessagesModelTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let room = "!a:davlin.io"

    private func model(
        _ transport: FakeTransport,
        texts: [String: String] = [:],
        now: Date = Self.now
    ) -> ScheduledMessagesModel {
        var store = ScheduledMessagePreviewStore(file: nil)
        for (delayId, text) in texts {
            store.set(text, for: delayId, sendAt: now.addingTimeInterval(3600))
        }
        return ScheduledMessagesModel(transport: transport, previewStore: store, now: { now })
    }

    private func registry(_ messages: [ScheduledMessage]) throws -> String {
        try ScheduledMessageDocument(messages: messages).jsonString()
    }

    private func entry(_ delayId: String, at offset: TimeInterval = 3600) -> ScheduledMessage {
        ScheduledMessage(delayId: delayId, roomId: Self.room, sendAt: Self.now.addingTimeInterval(offset))
    }

    // MARK: - Schedule

    @Test func scheduleSendsPlainTextAndRecordsTheEntry() async throws {
        let transport = FakeTransport()
        let model = model(transport)
        await model.refresh()

        let sendAt = Self.now.addingTimeInterval(3600)
        let message = try await model.schedule(text: "Lunch at noon?", roomId: Self.room, sendAt: sendAt)

        #expect(transport.scheduled.count == 1)
        #expect(transport.scheduled.first?.roomId == Self.room)
        #expect(transport.scheduled.first?.contentJSON == #"{"body":"Lunch at noon?","msgtype":"m.text"}"#)
        #expect(transport.scheduled.first?.delayMs == 3_600_000)
        #expect(message == ScheduledMessage(delayId: "d-new", roomId: Self.room, sendAt: sendAt))
        #expect(transport.stored.messages == [message])
        #expect(model.items(inRooms: [Self.room]) == [ScheduledMessageItem(message: message, text: "Lunch at noon?")])
    }

    @Test func aPassedTimeIsRefusedBeforeTheServer() async {
        let transport = FakeTransport()
        let model = model(transport)
        await #expect(throws: ScheduledMessageFailure.timePassed) {
            try await model.schedule(text: "late", roomId: Self.room, sendAt: Self.now.addingTimeInterval(0.5))
        }
        #expect(transport.scheduled.isEmpty)
    }

    @Test(arguments: [
        ScheduledMessageFailure.rateLimited(retryAfter: 2),
        .delayTooLarge,
        .forbidden,
        .unsupported,
    ])
    func aServerErrorRecordsNothing(failure: ScheduledMessageFailure) async {
        let transport = FakeTransport()
        transport.scheduleFailure = failure
        let model = model(transport)
        await #expect(throws: failure) {
            try await model.schedule(text: "hi", roomId: Self.room, sendAt: Self.now.addingTimeInterval(600))
        }
        #expect(transport.registry == nil)
        #expect(model.document.messages.isEmpty)
    }

    /// The app cannot show a message it did not record, so the server's
    /// copy is cancelled.
    @Test func aFailedRegistryWriteCancelsTheServerCopy() async {
        let transport = FakeTransport()
        transport.failsWrites = true
        let model = model(transport)
        await #expect(throws: ScheduledMessageFailure.registryWriteFailed) {
            try await model.schedule(text: "hi", roomId: Self.room, sendAt: Self.now.addingTimeInterval(600))
        }
        #expect(transport.updates.map(\.delayId) == ["d-new"])
        #expect(transport.updates.map(\.update) == [.cancel])
        #expect(model.previews.isEmpty)
    }

    @Test func aNewerRegistryIsReadOnly() async {
        let transport = FakeTransport()
        transport.registry = #"{"version":2,"messages":[]}"#
        let model = model(transport)
        await model.refresh()
        #expect(!model.isEditable)
        await #expect(throws: ScheduledMessageFailure.readOnly) {
            try await model.schedule(text: "hi", roomId: Self.room, sendAt: Self.now.addingTimeInterval(600))
        }
        #expect(transport.scheduled.isEmpty)
        #expect(transport.writeCount == 0)
    }

    // MARK: - Send now and cancel

    @Test func sendNowSendsAndDropsTheEntry() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1"), entry("d2")])
        let model = model(transport, texts: ["d1": "one", "d2": "two"])
        await model.refresh()

        try await model.sendNow(delayId: "d1")

        #expect(transport.updates.map(\.update) == [.send])
        #expect(transport.stored.messages.map(\.delayId) == ["d2"])
        #expect(model.previews == ["d2": "two"])
        #expect(model.busyDelayIds.isEmpty)
    }

    @Test func cancelCancelsAndDropsTheEntry() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1")])
        let model = model(transport, texts: ["d1": "one"])
        await model.refresh()

        try await model.cancel(delayId: "d1")

        #expect(transport.updates.map(\.update) == [.cancel])
        #expect(transport.stored.messages.isEmpty)
        #expect(model.previews.isEmpty)
    }

    /// Not found: sent or cancelled elsewhere. The entry drops, and the
    /// user is told.
    @Test func notFoundDropsTheEntryAndReportsIt() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1")])
        transport.updateFailures["d1"] = .notFound
        let model = model(transport, texts: ["d1": "one"])
        await model.refresh()

        await #expect(throws: ScheduledMessageFailure.notFound) {
            try await model.cancel(delayId: "d1")
        }
        #expect(transport.stored.messages.isEmpty)
        #expect(model.previews.isEmpty)
    }

    @Test func anotherErrorKeepsTheEntry() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1")])
        transport.updateFailures["d1"] = .rateLimited(retryAfter: nil)
        let model = model(transport, texts: ["d1": "one"])
        await model.refresh()

        await #expect(throws: ScheduledMessageFailure.rateLimited(retryAfter: nil)) {
            try await model.sendNow(delayId: "d1")
        }
        #expect(transport.stored.messages.map(\.delayId) == ["d1"])
        #expect(model.previews == ["d1": "one"])
    }

    // MARK: - Edit

    @Test func editCancelsAndSchedulesTheNewText() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1")])
        transport.nextDelayIds = ["d2"]
        let model = model(transport, texts: ["d1": "old text"])
        await model.refresh()

        let newTime = Self.now.addingTimeInterval(7200)
        let message = try await model.edit(delayId: "d1", text: "new text", sendAt: newTime)

        #expect(transport.updates.map(\.delayId) == ["d1"])
        #expect(transport.updates.map(\.update) == [.cancel])
        #expect(transport.scheduled.first?.contentJSON == #"{"body":"new text","msgtype":"m.text"}"#)
        #expect(message == ScheduledMessage(delayId: "d2", roomId: Self.room, sendAt: newTime))
        #expect(transport.stored.messages == [message])
        #expect(model.previews == ["d2": "new text"])
    }

    /// The old message was sent already: nothing new is scheduled, so it
    /// cannot send twice.
    @Test func editOfASentMessageSchedulesNothing() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1")])
        transport.updateFailures["d1"] = .notFound
        let model = model(transport, texts: ["d1": "old"])
        await model.refresh()

        await #expect(throws: ScheduledMessageEditFailure.notCancelled(.notFound)) {
            try await model.edit(delayId: "d1", text: "new", sendAt: Self.now.addingTimeInterval(600))
        }
        #expect(transport.scheduled.isEmpty)
        #expect(transport.stored.messages.isEmpty)
    }

    /// The cancel worked and the new schedule failed: the text comes back
    /// for the composer.
    @Test func aFailedRescheduleReturnsTheText() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1")])
        transport.scheduleFailure = .forbidden
        let model = model(transport, texts: ["d1": "old"])
        await model.refresh()

        await #expect(throws: ScheduledMessageEditFailure.notRescheduled(.forbidden, text: "new")) {
            try await model.edit(delayId: "d1", text: "new", sendAt: Self.now.addingTimeInterval(600))
        }
        #expect(transport.stored.messages.isEmpty)
    }

    // MARK: - Cleanup

    /// An entry stays until its time plus 30 seconds, then a read drops it
    /// and its text.
    @Test func refreshDropsSentEntries() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("sent", at: -31), entry("due", at: -10), entry("later")])
        let model = model(transport, texts: ["sent": "a", "due": "b", "later": "c"])
        await model.refresh()

        #expect(transport.stored.messages.map(\.delayId) == ["due", "later"])
        #expect(model.document.messages.map(\.delayId) == ["due", "later"])
        #expect(model.previews == ["due": "b", "later": "c"])
    }

    /// A read that lacks an entry keeps its text: after a relaunch the
    /// SDK's store can be older than this Mac's last write.
    @Test func aReadWithoutTheEntryKeepsTheText() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([])
        let model = model(transport, texts: ["d1": "kept"])
        await model.refresh()
        #expect(model.previews == ["d1": "kept"])
        #expect(model.items(inRooms: [Self.room]).isEmpty)
    }

    /// An unreadable registry keeps the texts.
    @Test func anUnreadableRegistryKeepsTheTexts() async {
        let transport = FakeTransport()
        transport.registry = "not json"
        let model = model(transport, texts: ["d1": "kept"])
        await model.refresh()
        #expect(!model.isEditable)
        #expect(model.previews == ["d1": "kept"])
    }

    /// Another device's message has no text here.
    @Test func anotherDevicesMessageHasNoText() async throws {
        let transport = FakeTransport()
        transport.registry = try registry([entry("d1")])
        let model = model(transport)
        await model.refresh()
        #expect(model.items(inRooms: [Self.room]).map(\.text) == [nil])
    }

    // MARK: - SDK errors

    @Test func mapsTheSDKErrors() {
        func failure(_ kind: ErrorKind, code: String = "", msg: String = "") -> ScheduledMessageFailure {
            LiveScheduledMessageTransport.failure(from: ClientError.MatrixApi(kind: kind, code: code, msg: msg, details: nil))
        }
        #expect(failure(.limitExceeded(retryAfterMs: 2500)) == .rateLimited(retryAfter: 2.5))
        #expect(failure(.limitExceeded(retryAfterMs: nil)) == .rateLimited(retryAfter: nil))
        #expect(failure(.forbidden) == .forbidden)
        #expect(failure(.notFound) == .notFound)
        #expect(failure(.unrecognized) == .unsupported)
        #expect(failure(.custom(errcode: "M_DELAY_TOO_LARGE")) == .delayTooLarge)
        #expect(failure(.custom(errcode: "ORG.MATRIX.MSC4140_DELAY_TOO_LARGE")) == .delayTooLarge)
        #expect(failure(.unknown, code: "M_DELAY_TOO_LARGE") == .delayTooLarge)
        #expect(failure(.unknown, code: "M_UNKNOWN", msg: "boom") == .other("boom"))
        #expect(LiveScheduledMessageTransport.failure(from: ClientError.Generic(msg: "offline", details: nil)) == .other("offline"))
    }
}
