import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The account's merged chats (M2.5, MATRIX-140), kept in global account
/// data under `MergedChatDocument.eventType`.
///
/// The same design as `LabelsModel` (MATRIX-77). The SDK has no change
/// listener for a custom account data type (`observeAccountDataEvent` takes
/// only the built-in types), so `MatrixClient` re-reads the local store when
/// sync starts, when the room list reaches `running`, and when a window
/// becomes active. The model also adopts each of its own writes at once.
/// Writes are read-modify-write and run one at a time; `MergedChatEchoGate`
/// covers the gap between a write and its sync echo, when the store still
/// holds the old document.
///
/// This model is storage only. It never calls a room API: everything a
/// merged chat does goes through the normal per-room calls (contract §11,
/// 2026-11-10).
@MainActor @Observable
public final class MergedChatsModel {
    /// The merged chats to show. Empty until the first read, and when the
    /// stored event cannot be read. A document of a newer version shows as
    /// read, but `isEditable` is false.
    public private(set) var document = MergedChatDocument()

    /// False when the stored event could not be read or came from a newer
    /// schema: every write is refused so that data this build does not
    /// understand is not overwritten.
    public private(set) var isEditable = true

    @ObservationIgnored private let client: ClientProtocol
    @ObservationIgnored private var echoGate = MergedChatEchoGate()
    @ObservationIgnored private var writeQueue: Task<Void, Never>?

    init(client: ClientProtocol) {
        self.client = client
    }

    // MARK: Reading

    /// Re-reads the merged chats from the SDK's local store.
    public func refresh() async {
        let result: MergedChatReadResult
        do {
            result = try await MergedChatDocument.read(client.accountData(eventType: MergedChatDocument.eventType))
        } catch {
            Logger.mergedChats.error("failed to read merged chats: \(String(describing: error), privacy: .public)")
            return
        }
        guard let accepted = echoGate.accept(result) else {
            Logger.mergedChats.debug("merged chats read is older than the last write; keeping the written document")
            return
        }
        adopt(accepted)
    }

    private func adopt(_ result: MergedChatReadResult) {
        if case let .unreadable(raw, reason) = result {
            Logger.mergedChats.error(
                "merged chats account data is unreadable; writes are off. reason=\(reason, privacy: .public) raw=\(raw, privacy: .private)"
            )
        } else if case let .parsed(stored) = result, !stored.document.isWritable {
            Logger.mergedChats.error(
                "merged chats account data has version \(stored.document.version, privacy: .public); writes are off"
            )
        }

        let document = result.document
        if document != self.document {
            self.document = document
        }
        let editable = result.writableBase != nil
        if editable != isEditable {
            isEditable = editable
        }
    }

    // MARK: Derived state

    /// The merged chat that holds `roomId`, if any.
    public func merge(containing roomId: String) -> MergedChat? {
        document.merge(containing: roomId)
    }

    /// The merged chat with this ID, if any.
    public func merge(id: String) -> MergedChat? {
        document.merge(id: id)
    }

    /// Every room that belongs to a merged chat. The chat list hides these
    /// rows and shows one row per merge instead.
    public var mergedRoomIds: Set<String> {
        document.mergedRoomIds
    }

    // MARK: Writing

    /// Applies `change` to the current merged chats and writes the result.
    ///
    /// Changes run in order, one at a time, each on the newest document, so
    /// a change should name merges by ID and state the value it wants, to
    /// stay correct when another device wrote in between. The document's
    /// invariants are restored after `change` (`MergedChatDocument
    /// .normalize()`). A change that leaves the document as it was writes
    /// nothing. The write is refused, and logged, when the stored event is
    /// unreadable or newer than this build (`isEditable`).
    ///
    /// To know a new merge's ID, pass one to `create(…id:)`:
    ///
    /// ```swift
    /// let id = UUID().uuidString
    /// model.mutate { $0.create(name: "Seth", rooms: [a, b], id: id) }
    /// ```
    ///
    /// - Returns: The queued write. Await its value to run code after the
    ///   write was sent (or refused); callers that do not care can drop it.
    @discardableResult
    public func mutate(_ change: @escaping (inout MergedChatDocument) -> Void) -> Task<Void, Never> {
        let previous = writeQueue
        let task = Task { [weak self] in
            await previous?.value
            await self?.write(change)
        }
        writeQueue = task
        return task
    }

    private func write(_ change: (inout MergedChatDocument) -> Void) async {
        let base: MergedChatStoredDocument
        if let pending = echoGate.pendingDocument() {
            // The store has not caught up with the last write yet.
            base = pending
        } else {
            let read: MergedChatReadResult
            do {
                read = try await MergedChatDocument.read(client.accountData(eventType: MergedChatDocument.eventType))
            } catch {
                Logger.mergedChats.error("failed to read merged chats before a write: \(String(describing: error), privacy: .public)")
                return
            }
            guard let writable = read.writableBase else {
                adopt(read)
                Logger.mergedChats.error("refusing to write merged chats: the stored document cannot be written by this build")
                return
            }
            base = writable
        }

        var updated = base
        updated.update(change)
        guard updated != base else {
            adopt(.parsed(base))
            return
        }

        do {
            try await client.setAccountData(eventType: MergedChatDocument.eventType, content: updated.jsonString())
            echoGate.didWrite(updated)
            adopt(.parsed(updated))
        } catch {
            Logger.mergedChats.error("failed to write merged chats: \(String(describing: error), privacy: .public)")
        }
    }
}
