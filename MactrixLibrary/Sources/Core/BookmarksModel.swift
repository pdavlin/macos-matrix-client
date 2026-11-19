import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The account's bookmarked messages (MATRIX-208), kept in global account
/// data under `BookmarkDocument.eventType`.
///
/// The same design as `MergedChatsModel` (MATRIX-140). The SDK has no change
/// listener for a custom account data type, so `MatrixClient` re-reads the
/// local store when sync starts, when the room list reaches `running`, and
/// when a window becomes active. The model adopts each of its own writes at
/// once. Writes are read-modify-write and run one at a time;
/// `AccountDataEchoGate` covers the gap between a write and its sync echo.
///
/// The document holds IDs and times only, never message text: account data
/// is not encrypted on the server (contract §11, 2026-11-19).
@MainActor @Observable
public final class BookmarksModel {
    /// The bookmarks to show. Empty until the first read, and when the
    /// stored event cannot be read.
    public private(set) var document = BookmarkDocument()

    /// Every bookmarked message, for the timeline rows' mark and menus.
    public private(set) var keys: Set<BookmarkKey> = []

    /// False when the stored event could not be read or came from a newer
    /// schema: every write is refused.
    public private(set) var isEditable = true

    @ObservationIgnored private let client: ClientProtocol
    @ObservationIgnored private var echoGate = AccountDataEchoGate<BookmarkDocument>()
    @ObservationIgnored private var writeQueue: Task<Void, Never>?

    init(client: ClientProtocol) {
        self.client = client
    }

    public func isBookmarked(roomId: String, eventId: String) -> Bool {
        keys.contains(BookmarkKey(roomId: roomId, eventId: eventId))
    }

    // MARK: Reading

    /// Re-reads the bookmarks from the SDK's local store.
    public func refresh() async {
        let result: BookmarkReadResult
        do {
            result = try await BookmarkDocument.read(client.accountData(eventType: BookmarkDocument.eventType))
        } catch {
            Logger.bookmarks.error("failed to read bookmarks: \(String(describing: error), privacy: .public)")
            return
        }
        let parsed: BookmarkDocument? = if case let .parsed(document) = result {
            document
        } else {
            nil
        }
        guard echoGate.accept(parsed) else {
            Logger.bookmarks.debug("bookmarks read is older than the last write; keeping the written document")
            return
        }
        adopt(result)
    }

    private func adopt(_ result: BookmarkReadResult) {
        if case let .unreadable(_, reason) = result {
            Logger.bookmarks.error("bookmarks account data is unreadable; writes are off. reason=\(reason, privacy: .public)")
        } else if case let .parsed(stored) = result, !stored.isWritable {
            Logger.bookmarks.error("bookmarks account data has version \(stored.version, privacy: .public); writes are off")
        }

        let document = result.document
        if document != self.document {
            self.document = document
            keys = document.keys
        }
        let editable = result.writableBase != nil
        if editable != isEditable {
            isEditable = editable
        }
    }

    // MARK: Writing

    /// Bookmarks the message, or removes its bookmark.
    ///
    /// The change states the wanted value, so it stays correct when it runs
    /// after another device's write. Changes run in order, one at a time.
    /// The write is refused, and logged, when `isEditable` is false.
    ///
    /// - Returns: The queued write. Await it to run code after the write was
    ///   sent or refused.
    @discardableResult
    public func setBookmarked(_ isBookmarked: Bool, roomId: String, eventId: String) -> Task<Void, Never> {
        let key = BookmarkKey(roomId: roomId, eventId: eventId)
        let savedAt = Date.now
        let previous = writeQueue
        let task = Task { [weak self] in
            await previous?.value
            await self?.write { $0.setBookmarked(key, isBookmarked, savedAt: savedAt) }
        }
        writeQueue = task
        return task
    }

    private func write(_ change: (inout BookmarkDocument) -> Void) async {
        let base: BookmarkDocument
        if let pending = echoGate.pendingDocument() {
            // The store has not caught up with the last write yet.
            base = pending
        } else {
            let read: BookmarkReadResult
            do {
                read = try await BookmarkDocument.read(client.accountData(eventType: BookmarkDocument.eventType))
            } catch {
                Logger.bookmarks.error("failed to read bookmarks before a write: \(String(describing: error), privacy: .public)")
                return
            }
            guard let writable = read.writableBase else {
                adopt(read)
                Logger.bookmarks.error("refusing to write bookmarks: the stored document cannot be written by this build")
                return
            }
            base = writable
        }

        var updated = base
        change(&updated)
        guard updated != base else {
            adopt(.parsed(base))
            return
        }

        do {
            try await client.setAccountData(eventType: BookmarkDocument.eventType, content: updated.jsonString())
            echoGate.didWrite(updated)
            adopt(.parsed(updated))
        } catch {
            Logger.bookmarks.error("failed to write bookmarks: \(String(describing: error), privacy: .public)")
        }
    }
}
