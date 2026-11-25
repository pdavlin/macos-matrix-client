import Foundation
import Observation

/// The session's copy of the account's reaction use (MATRIX-262), and its
/// writes to account data.
///
/// The same design as the labels, the inbox states, and the bookmarks: the
/// SDK has no change listener for a custom account data type, so `Core`
/// calls `refresh()` when sync starts, when the room list reaches `running`,
/// and when a window becomes active. Writes are read-modify-write and run
/// one at a time. `AccountDataEchoGate` covers the gap between a write and
/// its sync echo.
///
/// A use shows at once in `document`. The write waits `writeDelay`, so a
/// burst of reactions makes one write. Uses that are not written yet stay
/// on top of each read, so a read never takes them off the screen. A use
/// that a write could not send is sent with the next write.
///
/// The store has no SDK of its own: `Transport` gives it the read and the
/// write, so tests run with a fake.
///
/// Usage (in `Core`):
/// ```swift
/// let store = ReactionUsageStore(transport: transport)
/// await store.refresh()
/// store.record("🎉", inRoom: roomId)
/// ```
@MainActor @Observable
public final class ReactionUsageStore {
    /// What the store reads from and writes to.
    public struct Transport: Sendable {
        /// Reads the account data content, or nil when the event is unset.
        public let read: @MainActor () async throws -> String?
        /// Writes the account data content.
        public let write: @MainActor (_ content: String) async throws -> Void
        /// Takes one line for the log when a read or a write fails, or a
        /// write is refused. The line holds an error description, never
        /// message text.
        public let report: @MainActor (String) -> Void

        public init(
            read: @escaping @MainActor () async throws -> String?,
            write: @escaping @MainActor (_ content: String) async throws -> Void,
            report: @escaping @MainActor (String) -> Void
        ) {
            self.read = read
            self.write = write
            self.report = report
        }
    }

    /// The wait between the first use of a burst and its write.
    public static let writeDelay: Duration = .seconds(2)

    /// The use to rank by: the stored document, with the uses that are not
    /// written yet on top.
    public private(set) var document = ReactionUsageDocument()

    /// False when the stored event could not be read or came from a newer
    /// schema: every write is refused. The uses of this session still show.
    public private(set) var isEditable = true

    /// One use that is not written yet.
    private struct Use {
        let key: String
        let roomId: String
        let date: Date
    }

    @ObservationIgnored private let transport: Transport
    @ObservationIgnored private let wait: @MainActor () async -> Void
    @ObservationIgnored private var echoGate = AccountDataEchoGate<ReactionUsageDocument>()
    /// The document of the last read that was adopted, or of the last write.
    @ObservationIgnored private var stored = ReactionUsageDocument()
    /// The uses that no write has sent yet, oldest first.
    @ObservationIgnored private var unsent: [Use] = []
    @ObservationIgnored private var scheduledWrite: Task<Void, Never>?
    @ObservationIgnored private var writeQueue: Task<Void, Never>?

    /// - Parameters:
    ///   - transport: The account data read and write.
    ///   - wait: The wait before a burst's write. Tests pass their own.
    public init(
        transport: Transport,
        wait: @escaping @MainActor () async -> Void = { try? await Task.sleep(for: ReactionUsageStore.writeDelay) }
    ) {
        self.transport = transport
        self.wait = wait
    }

    // MARK: Reading

    /// Re-reads the use from the store. While a write's echo has not come
    /// back, the read is ignored and the written document stays.
    public func refresh() async {
        let result: ReactionUsageReadResult
        do {
            result = try await ReactionUsageDocument.read(transport.read())
        } catch {
            transport.report("failed to read reaction usage: \(String(describing: error))")
            return
        }
        guard echoGate.accept(result.parsedDocument) else { return }
        adopt(result)
    }

    private func adopt(_ result: ReactionUsageReadResult) {
        if case let .unreadable(_, reason) = result {
            transport.report("reaction usage account data is unreadable; writes are off. reason=\(reason)")
        } else if case let .parsed(document) = result, !document.isWritable {
            transport.report("reaction usage account data has version \(document.version); writes are off")
        }
        stored = result.document
        let editable = result.writableBase != nil
        if editable != isEditable {
            isEditable = editable
        }
        show()
    }

    /// Shows the stored document with the unsent uses on top.
    private func show() {
        let shown = unsent.reduce(into: stored) { $0.record($1.key, inRoom: $1.roomId, at: $1.date) }
        if shown != document {
            document = shown
        }
    }

    // MARK: Recording

    /// Records the outcome of a reaction toggle in `roomId`. An added
    /// reaction is a use; a removed one is not, and changes nothing.
    public func recordToggle(of key: String, inRoom roomId: String, wasAdded: Bool, at date: Date = .now) {
        guard wasAdded else { return }
        record(key, inRoom: roomId, at: date)
    }

    /// Records one use of `key` in `roomId`: a reaction that was added, or
    /// an emoji picked in the composer. It shows at once; the write follows
    /// after the wait, with the other uses of the burst.
    public func record(_ key: String, inRoom roomId: String, at date: Date = .now) {
        guard !key.isEmpty, !roomId.isEmpty else { return }
        unsent.append(Use(key: key, roomId: roomId, date: date))
        show()
        scheduleWrite()
    }

    private func scheduleWrite() {
        guard scheduledWrite == nil else { return }
        scheduledWrite = Task { [weak self] in
            await self?.wait()
            guard let self else { return }
            scheduledWrite = nil
            await flush().value
        }
    }

    // MARK: Writing

    /// Writes the unsent uses now, after the write in flight.
    ///
    /// - Returns: The queued write. Await it to run code after the write
    ///   was sent or refused.
    @discardableResult
    public func flush() -> Task<Void, Never> {
        let previous = writeQueue
        let task = Task { [weak self] in
            await previous?.value
            await self?.write()
        }
        writeQueue = task
        return task
    }

    /// Waits for the scheduled write and the writes in the queue.
    public func waitForWrites() async {
        await scheduledWrite?.value
        await writeQueue?.value
    }

    private func write() async {
        let uses = unsent
        guard !uses.isEmpty else { return }
        let base: ReactionUsageDocument
        if let pending = echoGate.pendingDocument() {
            // The store has not caught up with the last write yet.
            base = pending
        } else {
            let read: ReactionUsageReadResult
            do {
                read = try await ReactionUsageDocument.read(transport.read())
            } catch {
                transport.report("failed to read reaction usage before a write: \(String(describing: error))")
                return
            }
            guard let writable = read.writableBase else {
                adopt(read)
                transport.report("refusing to write reaction usage: the stored document cannot be written by this build")
                return
            }
            base = writable
        }

        let updated = uses.reduce(into: base) { $0.record($1.key, inRoom: $1.roomId, at: $1.date) }
        do {
            try await transport.write(updated.jsonString())
        } catch {
            transport.report("failed to write reaction usage: \(String(describing: error))")
            return
        }
        // Uses recorded while the write ran stay in the list, after these.
        unsent.removeFirst(uses.count)
        echoGate.didWrite(updated)
        adopt(.parsed(updated))
    }
}
