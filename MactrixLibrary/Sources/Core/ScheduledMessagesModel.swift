import Foundation
import Models
import Observation
import OSLog

/// What an update does to a scheduled message (MATRIX-212). The SDK's
/// `DelayedEventUpdateAction` also has `restart`, which Send Later does not
/// use: it restarts the original delay and cannot set a new time.
public enum ScheduledMessageUpdate: Equatable, Sendable {
    case send
    case cancel
}

/// The SDK side of Send Later (MATRIX-212), behind a protocol so the tests
/// run the model over a fake. `LiveScheduledMessageTransport` is the SDK
/// one.
@MainActor
public protocol ScheduledMessageTransport: AnyObject {
    /// The registry's account data content, or nil when it is unset.
    func readRegistry() async throws -> String?
    /// Writes the registry's account data content.
    func writeRegistry(_ json: String) async throws
    /// Schedules the event content `contentJSON` in `roomId`, `delayMs`
    /// from now. Returns the server's delay ID.
    func scheduleMessage(roomId: String, contentJSON: String, delayMs: UInt64) async throws(ScheduledMessageFailure) -> String
    /// Sends now or cancels the delayed event `delayId`.
    func updateDelayedEvent(delayId: String, update: ScheduledMessageUpdate) async throws(ScheduledMessageFailure)
}

/// Why an Edit failed (MATRIX-212). Edit is a cancel, then a new schedule.
public enum ScheduledMessageEditFailure: Error, Equatable, Sendable {
    /// The cancel failed. The old message is still scheduled, or it was
    /// already sent (`notFound`).
    case notCancelled(ScheduledMessageFailure)
    /// The cancel worked, but the new schedule failed: the edited text is
    /// not scheduled anywhere. The composer gets it back.
    case notRescheduled(ScheduledMessageFailure, text: String)

    public var failure: ScheduledMessageFailure {
        switch self {
        case let .notCancelled(failure), let .notRescheduled(failure, _): failure
        }
    }
}

/// The account's scheduled messages (MATRIX-212).
///
/// The server holds each message (MSC4140, `Room.sendDelayedEvent`). The
/// FFI cannot list delayed events, so the model keeps a registry in global
/// account data under `ScheduledMessageDocument.eventType`, with the delay
/// ID, the room, and the due time of each message. The text of a message
/// stays in a local file on the Mac that scheduled it
/// (`ScheduledMessagePreviewStore`).
///
/// The registry follows the design of `BookmarksModel` (MATRIX-208): the
/// SDK has no listener for a custom account data type, so `MatrixClient`
/// re-reads it when sync starts, when the room list reaches `running`, and
/// when a window becomes active. Writes are read-modify-write and run one
/// at a time; `AccountDataEchoGate` covers the gap before the sync echo.
///
/// An entry leaves the registry when the server has sent it (its due time
/// plus `ScheduledMessageDocument.sendGrace`), after Send Now or Cancel,
/// and when an update returns not found (sent or cancelled elsewhere).
@MainActor @Observable
public final class ScheduledMessagesModel {
    /// The registry to show. Empty until the first read, and when the stored
    /// event cannot be read.
    public private(set) var document = ScheduledMessageDocument()

    /// False when the stored event could not be read or came from a newer
    /// schema: every change is refused.
    public private(set) var isEditable = true

    /// The local text of each delay ID this Mac scheduled.
    public private(set) var previews: [String: String] = [:]

    /// The delay IDs with a Send Now, Cancel, or Edit in flight.
    public private(set) var busyDelayIds: Set<String> = []

    @ObservationIgnored private let transport: ScheduledMessageTransport
    @ObservationIgnored private var previewStore: ScheduledMessagePreviewStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var echoGate = AccountDataEchoGate<ScheduledMessageDocument>()
    @ObservationIgnored private var writeQueue: Task<Bool, Never>?
    @ObservationIgnored private var cleanupTimer: Task<Void, Never>?

    /// - Parameters:
    ///   - transport: the SDK calls.
    ///   - previewStore: the local texts.
    ///   - now: the clock, for the tests.
    public init(
        transport: ScheduledMessageTransport,
        previewStore: ScheduledMessagePreviewStore,
        now: @escaping () -> Date = { .now }
    ) {
        self.transport = transport
        self.previewStore = previewStore
        self.now = now
        previews = previewStore.texts
    }

    /// The scheduled messages of `roomIds` with their local text, the
    /// earliest due first.
    public func items(inRooms roomIds: Set<String>) -> [ScheduledMessageItem] {
        document.messages(inRooms: roomIds).map { ScheduledMessageItem(message: $0, text: previews[$0.delayId]) }
    }

    /// Stops the cleanup timer (sign-out).
    public func stop() {
        cleanupTimer?.cancel()
        cleanupTimer = nil
    }

    // MARK: Reading

    /// Re-reads the registry from the SDK's local store, then removes the
    /// entries the server has sent.
    public func refresh() async {
        let result: ScheduledMessageReadResult
        do {
            result = try await ScheduledMessageDocument.read(transport.readRegistry())
        } catch {
            Logger.scheduled.error("failed to read scheduled messages: \(String(describing: error), privacy: .public)")
            return
        }
        let parsed: ScheduledMessageDocument? = if case let .parsed(document) = result {
            document
        } else {
            nil
        }
        guard echoGate.accept(parsed) else {
            Logger.scheduled.debug("scheduled messages read is older than the last write; keeping the written document")
            return
        }
        adopt(result)
        await removeSent()
    }

    private func adopt(_ result: ScheduledMessageReadResult) {
        if case let .unreadable(_, reason) = result {
            Logger.scheduled.error("scheduled messages account data is unreadable; writes are off. reason=\(reason, privacy: .public)")
        } else if case let .parsed(stored) = result, !stored.isWritable {
            Logger.scheduled.error("scheduled messages account data has version \(stored.version, privacy: .public); writes are off")
        }

        let document = result.document
        if document != self.document {
            self.document = document
        }
        let editable = result.writableBase != nil
        if editable != isEditable {
            isEditable = editable
        }
        // A text whose message the server has sent is no longer needed.
        previewStore.removeExpired(at: now())
        syncPreviews()
        armCleanup()
    }

    private func syncPreviews() {
        if previews != previewStore.texts {
            previews = previewStore.texts
        }
    }

    // MARK: Actions

    /// Schedules `text` as a plain-text message in `roomId` at `sendAt`.
    ///
    /// The SDK encrypts the content now when the room is encrypted. The
    /// registry gets the new entry, and this Mac keeps the text. When the
    /// registry write fails, the server's copy is cancelled, so no message
    /// is scheduled that the app cannot show.
    ///
    /// - Returns: the new entry.
    @discardableResult
    public func schedule(text: String, roomId: String, sendAt: Date) async throws(ScheduledMessageFailure) -> ScheduledMessage {
        guard isEditable else { throw .readOnly }
        let delay = sendAt.timeIntervalSince(now())
        guard delay >= 1 else { throw .timePassed }
        let contentJSON: String
        do {
            contentJSON = try ScheduledMessageContent(body: text).jsonString()
        } catch {
            throw .other(String(describing: error))
        }

        let delayId = try await transport.scheduleMessage(
            roomId: roomId,
            contentJSON: contentJSON,
            delayMs: UInt64((delay * 1000).rounded())
        )
        let message = ScheduledMessage(delayId: delayId, roomId: roomId, sendAt: sendAt)
        guard await mutate({ $0.add(message) }).value else {
            Logger.scheduled.error("registry write failed; cancelling delayed event \(delayId, privacy: .public)")
            do {
                try await transport.updateDelayedEvent(delayId: delayId, update: .cancel)
            } catch {
                Logger.scheduled.error("failed to cancel unrecorded delayed event: \(String(describing: error), privacy: .public)")
            }
            throw .registryWriteFailed
        }
        previewStore.set(text, for: delayId, sendAt: sendAt)
        syncPreviews()
        Logger.scheduled.info("scheduled message \(delayId, privacy: .public) in \(roomId, privacy: .public)")
        return message
    }

    /// Sends the message `delayId` now.
    public func sendNow(delayId: String) async throws(ScheduledMessageFailure) {
        try await update(delayId: delayId, update: .send)
    }

    /// Cancels the message `delayId`.
    public func cancel(delayId: String) async throws(ScheduledMessageFailure) {
        try await update(delayId: delayId, update: .cancel)
    }

    /// Replaces the message `delayId` with `text` at `sendAt`: a cancel,
    /// then a new schedule with a new delay ID. MSC4140 has no edit.
    @discardableResult
    public func edit(delayId: String, text: String, sendAt: Date) async throws(ScheduledMessageEditFailure) -> ScheduledMessage {
        guard let old = document.message(delayId: delayId) else { throw .notCancelled(.notFound) }
        do throws(ScheduledMessageFailure) {
            try await update(delayId: delayId, update: .cancel)
        } catch {
            throw .notCancelled(error)
        }
        do throws(ScheduledMessageFailure) {
            return try await schedule(text: text, roomId: old.roomId, sendAt: sendAt)
        } catch {
            throw .notRescheduled(error, text: text)
        }
    }

    /// Runs `update` on the server, then drops the entry. Not found means
    /// the server already sent or cancelled it: the entry drops, and the
    /// error goes on so the user knows.
    private func update(delayId: String, update: ScheduledMessageUpdate) async throws(ScheduledMessageFailure) {
        guard isEditable else { throw .readOnly }
        busyDelayIds.insert(delayId)
        defer { busyDelayIds.remove(delayId) }
        do throws(ScheduledMessageFailure) {
            try await transport.updateDelayedEvent(delayId: delayId, update: update)
        } catch .notFound {
            await drop(delayIds: [delayId])
            throw .notFound
        }
        await drop(delayIds: [delayId])
    }

    /// Removes the entries and their texts. When the write fails, the
    /// entries stay, with their texts, until the next cleanup.
    private func drop(delayIds: Set<String>) async {
        guard await mutate({ $0.remove(delayIds: delayIds) }).value else { return }
        for delayId in delayIds {
            previewStore.remove(delayId)
        }
        syncPreviews()
    }

    // MARK: Cleanup

    /// Removes the entries the server has sent: due time plus the grace.
    func removeSent() async {
        guard isEditable else { return }
        let sent = document.sentMessages(at: now())
        guard !sent.isEmpty else { return }
        Logger.scheduled.info("removing \(sent.count, privacy: .public) sent scheduled message(s)")
        await drop(delayIds: Set(sent.map(\.delayId)))
    }

    /// Arms the timer for the next entry that leaves the registry.
    private func armCleanup() {
        cleanupTimer?.cancel()
        guard let next = document.nextCleanupDate else {
            cleanupTimer = nil
            return
        }
        let delay = next.timeIntervalSince(now())
        cleanupTimer = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.removeSent()
        }
    }

    // MARK: Writing

    /// Applies `change` to the newest registry and writes the result.
    /// Changes run in order, one at a time.
    ///
    /// - Returns: the queued write. Its value is false when the write was
    ///   refused or failed; a change that leaves the registry as it was
    ///   counts as written.
    @discardableResult
    func mutate(_ change: @escaping (inout ScheduledMessageDocument) -> Void) -> Task<Bool, Never> {
        let previous = writeQueue
        let task = Task { [weak self] in
            _ = await previous?.value
            return await self?.write(change) ?? false
        }
        writeQueue = task
        return task
    }

    private func write(_ change: (inout ScheduledMessageDocument) -> Void) async -> Bool {
        let base: ScheduledMessageDocument
        if let pending = echoGate.pendingDocument() {
            // The store has not caught up with the last write yet.
            base = pending
        } else {
            let read: ScheduledMessageReadResult
            do {
                read = try await ScheduledMessageDocument.read(transport.readRegistry())
            } catch {
                Logger.scheduled.error("failed to read scheduled messages before a write: \(String(describing: error), privacy: .public)")
                return false
            }
            guard let writable = read.writableBase else {
                adopt(read)
                Logger.scheduled.error("refusing to write scheduled messages: the stored document cannot be written by this build")
                return false
            }
            base = writable
        }

        var updated = base
        change(&updated)
        guard updated != base else {
            adopt(.parsed(base))
            return true
        }

        do {
            try await transport.writeRegistry(updated.jsonString())
            echoGate.didWrite(updated)
            adopt(.parsed(updated))
            return true
        } catch {
            Logger.scheduled.error("failed to write scheduled messages: \(String(describing: error), privacy: .public)")
            return false
        }
    }
}
