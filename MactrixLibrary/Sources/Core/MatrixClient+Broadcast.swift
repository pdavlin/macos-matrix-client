import Foundation
import MatrixRustSDK
import Models
import OSLog

/// Why a broadcast send did not reach a room's send queue (MATRIX-168).
public enum BroadcastSendError: LocalizedError {
    /// The Matrix client is gone (signed out).
    case clientUnavailable
    /// The client does not know the room.
    case unknownRoom

    public var errorDescription: String? {
        switch self {
        case .clientUnavailable: "The account is signed out."
        case .unknownRoom: "The chat was not found."
        }
    }
}

// MARK: - Broadcast send (MATRIX-168)

/// The real send of a broadcast (contract §11, 2026-11-16). `Models.BroadcastRun`
/// calls it once per target, one at a time.
///
/// The send goes through SDK calls only (hard rule 1), the composer's text
/// path without a reply and without mentions:
///
/// - The room comes from the sidebar's room list, else from
///   `Client.getRoom(roomId:)`, as a forward's target does.
/// - If the text can hold a `:name:` token, the room's image packs load
///   first, and `ComposerEmojiMarkup.resolving(markdown:packs:)` resolves
///   the tokens against that room's packs, as the composer does. So the
///   same text can give a different emoji image in each workspace, and a
///   token a room does not know stays as text there.
/// - `messageEventContentFromMarkdown(md:)` builds the content, the call
///   the composer uses.
/// - `Timeline.send(msg:)` on a timeline from
///   `Room.timelineWithConfiguration(configuration:)` puts the message in
///   the room's send queue. The timeline is a local value with no listener,
///   so it is released when the call returns. No timeline stays alive after
///   the run.
///
/// The call returns when the send queue has the message. From then on the
/// queue owns it: a later failure shows on the local echo in that chat,
/// with retry and discard, as for a message from the composer.
public extension MatrixClient {
    /// The pause between two rooms of a broadcast.
    static let broadcastPause: Duration = .milliseconds(400)

    /// Puts one broadcast message into a room's send queue.
    ///
    /// - Parameters:
    ///   - text: The message, as typed. Markdown, and `:name:` tokens of the
    ///     room's image packs.
    ///   - roomId: The room the message goes to.
    /// - Throws: `BroadcastSendError`, or the SDK error.
    func sendBroadcast(text: String, toRoom roomId: String) async throws {
        guard let sdkClient: ClientProtocol = client else { throw BroadcastSendError.clientUnavailable }
        let sidebarRoom: MatrixRustSDK.Room? = rooms.first(where: { $0.id == roomId })?.room
        guard let room = try sidebarRoom ?? sdkClient.getRoom(roomId: roomId) else {
            throw BroadcastSendError.unknownRoom
        }
        var packs: [ImagePack] = []
        if BroadcastText.mayHoldEmojiToken(text) {
            packs = await loadedImagePacks(forRoom: roomId)
        }
        try await Self.sendBroadcast(text: text, to: room, packs: packs)
        Logger.matrixClient.info("broadcast: queued a message for \(roomId)")
    }

    /// Builds the content and puts it into the room's send queue.
    ///
    /// - Parameters:
    ///   - text: The message, as typed.
    ///   - room: The SDK room.
    ///   - packs: The room's image packs, for the `:name:` tokens.
    static func sendBroadcast(text: String, to room: MatrixRustSDK.Room, packs: [ImagePack]) async throws {
        let markdown = ComposerEmojiMarkup.resolving(markdown: text, packs: packs)
        let message: RoomMessageEventContentWithoutRelation = messageEventContentFromMarkdown(md: markdown)
        let timeline: Timeline = try await room.timelineWithConfiguration(configuration: forwardTimelineConfiguration)
        _ = try await timeline.send(msg: message)
    }
}
