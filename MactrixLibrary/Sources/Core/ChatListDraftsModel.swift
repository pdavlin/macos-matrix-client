import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The saved composer drafts the chat list shows (MATRIX-224): the "Draft:"
/// prefix on a row and the Drafts list filter.
///
/// The SDK's state store holds each room's draft
/// (`Room.loadComposerDraft(threadRoot:)`). The list does not read it for
/// each row on each update: `loadAll(rooms:)` reads every room one time
/// when sync starts, and the composer then reports each save and clear
/// (`roomDraftDidChange(roomId:draft:)`), so the cache stays the same as
/// the store without a second read. Only the main timeline's draft counts
/// (thread root nil). A merged chat's draft is in memory only
/// (`MergedComposerDrafts`), and the merged composer reports it through
/// `mergedDraftDidChange(mergeId:text:)`.
@MainActor @Observable
public final class ChatListDraftsModel {
    /// The row text of each draft.
    public private(set) var drafts = ChatListDrafts()

    /// Rooms the composer reported in this session. The first read does not
    /// overwrite them: the composer's report is newer.
    @ObservationIgnored private var reportedRoomIds: Set<String> = []
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    public init() {}

    /// Reads the main-timeline draft of each room one time. Later calls do
    /// nothing until `reset()`. Spaces are skipped. The read runs off the
    /// main actor and writes the result in one assignment.
    ///
    /// - Parameter rooms: the client's rooms (`Client.rooms()`).
    public func loadAll(rooms: [MatrixRustSDK.Room]) {
        guard loadTask == nil else { return }
        loadTask = Task { [weak self] in
            let start = ContinuousClock.now
            let found = await Task.detached(priority: .utility) {
                await Self.readDrafts(of: rooms)
            }.value
            guard let self, !Task.isCancelled else { return }
            self.apply(found)
            let elapsed = start.duration(to: .now)
            Logger.matrixClient.info(
                """
                chat list drafts: read \(rooms.count, privacy: .public) rooms, \
                \(found.count, privacy: .public) drafts, \
                \(elapsed.wholeMicroseconds, privacy: .public) us
                """
            )
        }
    }

    /// The composer saved (`draft`) or cleared (nil) the main-timeline
    /// draft of a room.
    public func roomDraftDidChange(roomId: String, draft: ComposerDraft?) {
        reportedRoomIds.insert(roomId)
        let text = draft?.chatListText
        guard drafts.rooms[roomId] != text else { return }
        drafts.rooms[roomId] = text
    }

    /// The merged composer saved its draft. An empty text clears it.
    ///
    /// - Parameters:
    ///   - mergeId: the merged chat's ID.
    ///   - text: the draft text the merged composer keeps
    ///     (`MergedComposerDrafts.text(forMerge:)`).
    public func mergedDraftDidChange(mergeId: String, text: String) {
        let row = ChatListDraftText.previewText(draftText: text, kind: .newMessage)
        guard drafts.merges[mergeId] != row else { return }
        drafts.merges[mergeId] = row
    }

    /// Drops every draft and stops a read, for the sign-out.
    public func reset() {
        loadTask?.cancel()
        loadTask = nil
        reportedRoomIds.removeAll()
        drafts = ChatListDrafts()
    }

    private func apply(_ found: [String: String]) {
        var rooms = drafts.rooms
        for (roomId, text) in found where !reportedRoomIds.contains(roomId) {
            rooms[roomId] = text
        }
        if rooms != drafts.rooms {
            drafts.rooms = rooms
        }
    }

    private nonisolated static func readDrafts(of rooms: [MatrixRustSDK.Room]) async -> [String: String] {
        var found: [String: String] = [:]
        for room in rooms where !room.isSpace() {
            guard !Task.isCancelled else { break }
            do {
                if let text = try await room.loadComposerDraft(threadRoot: nil)?.chatListText {
                    found[room.id()] = text
                }
            } catch {
                Logger.matrixClient.error("chat list drafts: read failed for \(room.id(), privacy: .public): \(error)")
            }
        }
        return found
    }
}

extension MatrixRustSDK.ComposerDraft {
    /// The row text of this draft (`ChatListDraftText`), or nil when the
    /// row shows no draft.
    var chatListText: String? {
        ChatListDraftText.previewText(draftText: plainText, kind: draftType.chatListKind)
    }
}

extension MatrixRustSDK.ComposerDraftType {
    var chatListKind: ChatListDraftKind {
        switch self {
        case .newMessage: .newMessage
        case .reply: .reply
        case .edit: .edit
        }
    }
}
