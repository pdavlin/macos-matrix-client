import Foundation
import MatrixRustSDK
import Models
import OSLog
import UniformTypeIdentifiers

/// One message to forward (MATRIX-112, M2-B5, D-4).
///
/// Built only for a sent message (it has an event ID) whose content
/// forwards: see `Models.MessageForwardContent.decide(type:body:media:)`.
public struct MessageForwardRequest {
    /// The event ID of the original message.
    public let eventId: String
    /// What the forward sends again, as plain values for the sheet.
    public let content: Models.MessageForwardContent
    /// The original SDK content. A media forward reads the media source and
    /// the info fields from it.
    let messageType: MatrixRustSDK.MessageType

    /// - Returns: nil for a local echo, and for content that does not forward.
    public init?(event: MatrixRustSDK.EventTimelineItem) {
        guard case let .eventId(eventId) = event.eventOrTransactionId,
              case let .msgLike(msgLike) = event.content,
              case let .message(message) = msgLike.kind,
              let content = Models.MessageForwardContent.decide(for: message.msgType)
        else { return nil }
        self.eventId = eventId
        self.content = content
        self.messageType = message.msgType
    }
}

/// The room a forward goes to.
public struct MessageForwardTarget {
    /// The SDK room. The forward opens a timeline on it for the send.
    public let room: MatrixRustSDK.Room
    /// The room's display name, or nil when the SDK has none.
    public let name: String?

    public var id: String {
        room.id()
    }
}

/// The forward flow of one room view: SDK request and room.
public typealias LiveMessageForwardFlow = MessageForwardFlow<MessageForwardRequest, MessageForwardTarget>

public enum MessageForwardError: Error {
    /// The Matrix client is gone (signed out).
    case clientUnavailable
}

// MARK: - Text-or-media decision

public extension Models.MessageForwardContent {
    /// The forward decision for an SDK message type. Exhaustive with no
    /// `default`, so a new SDK case has to be sorted here.
    static func decide(for msgType: MatrixRustSDK.MessageType) -> Self? {
        switch msgType {
        case let .text(content):
            return decide(type: .text, body: content.body)
        case let .notice(content):
            return decide(type: .notice, body: content.body)
        case let .emote(content):
            return decide(type: .emote, body: content.body)
        case let .location(content):
            return decide(type: .location, body: content.body)
        case let .image(content):
            let media = MessageForwardMedia(
                kind: .image, filename: content.filename, caption: content.caption, byteCount: content.info?.size
            )
            return decide(type: .image, body: "", media: media)
        case let .video(content):
            let media = MessageForwardMedia(
                kind: .video, filename: content.filename, caption: content.caption, byteCount: content.info?.size
            )
            return decide(type: .video, body: "", media: media)
        case let .audio(content):
            let media = MessageForwardMedia(
                kind: .audio, filename: content.filename, caption: content.caption, byteCount: content.info?.size
            )
            return decide(type: .audio, body: "", media: media)
        case let .file(content):
            let media = MessageForwardMedia(
                kind: .file, filename: content.filename, caption: content.caption, byteCount: content.info?.size
            )
            return decide(type: .file, body: "", media: media)
        case let .gallery(content):
            return decide(type: .gallery, body: content.body)
        case let .other(_, body):
            return decide(type: .other, body: body)
        }
    }
}

// MARK: - Forward request (MATRIX-112)

public extension LiveTimeline {
    /// Starts a forward of a message: the room view opens the picker.
    ///
    /// - Parameter event: The message. Nothing happens if it does not
    ///   forward.
    func requestForward(of event: MatrixRustSDK.EventTimelineItem) {
        guard let request = MessageForwardRequest(event: event) else {
            Logger.liveTimeline.error("forward requested for a message that does not forward: \(event.eventOrTransactionId.id)")
            return
        }
        forwarding.start(request)
    }
}

// MARK: - Forward send (MATRIX-112)

/// The forward goes through SDK calls only (D-4, hard rule 1):
///
/// - The target room comes from the sidebar's room list, else from
///   `Client.getRoom(roomId:)`: the lookup `MainView.onRoomSelected` uses.
/// - The send uses a timeline the forward opens on the target room with
///   `Room.timelineWithConfiguration(configuration:)`, as `LiveTimeline`
///   does. It is a local value with no listener, so it is released when the
///   send is queued. The room's send queue owns the message from then on.
/// - Text: `messageEventContentFromMarkdown(md:)`, `withMentions(mentions:)`,
///   and `Timeline.send(msg:)`, the composer's send path.
/// - Media: `Client.getMediaFile(...)` downloads the file (the SDK decrypts
///   it), then `sendImage`/`sendVideo`/`sendAudio`/`sendFile` upload it
///   again (the SDK encrypts it when the target room is encrypted), the
///   MATRIX-106 send calls. The file handle stays alive until the join
///   handle returns.
public extension MatrixClient {
    /// The room to forward to.
    ///
    /// - Parameter roomId: The picked room ID.
    /// - Returns: nil when the client does not know the room.
    func forwardTarget(roomId: String) -> MessageForwardTarget? {
        let room: MatrixRustSDK.Room?
        if let sidebarRoom = rooms.first(where: { $0.id == roomId }) {
            room = sidebarRoom.room
        } else if let sdkClient: ClientProtocol = client {
            do {
                room = try sdkClient.getRoom(roomId: roomId)
            } catch {
                Logger.matrixClient.error("forward: no room \(roomId): \(error)")
                room = nil
            }
        } else {
            room = nil
        }
        guard let room else { return nil }
        return MessageForwardTarget(room: room, name: room.displayName())
    }

    /// Puts a forward into the target room's send queue.
    ///
    /// It returns when the SDK has the message: for media, after the
    /// download, when the upload is queued. The upload progress then shows
    /// on the local echo in the target room (MATRIX-107).
    ///
    /// - Parameters:
    ///   - request: The message to forward.
    ///   - target: The room to forward to.
    /// - Throws: `MessageForwardError.clientUnavailable`, or the SDK error.
    func forward(_ request: MessageForwardRequest, to target: MessageForwardTarget) async throws {
        guard let sdkClient: ClientProtocol = client else { throw MessageForwardError.clientUnavailable }
        let timeline: Timeline = try await target.room.timelineWithConfiguration(configuration: Self.forwardTimelineConfiguration)
        switch request.content {
        case let .text(body):
            let outgoing = MessageForwardContent.outgoingText(body: body)
            let markdownContent = messageEventContentFromMarkdown(md: outgoing.markdown)
            let message: RoomMessageEventContentWithoutRelation = outgoing.mentionedUserIds.isEmpty
                ? markdownContent
                : markdownContent.withMentions(mentions: MatrixRustSDK.Mentions(userIds: outgoing.mentionedUserIds, room: false))
            _ = try await timeline.send(msg: message)
        case .media:
            try await Self.forwardMedia(request.messageType, client: sdkClient, timeline: timeline)
        }
        Logger.matrixClient.info("forwarded \(request.eventId) to \(target.id)")
    }

    /// A live timeline for the send only. The forward adds no listener to
    /// it, and it reports no decryption failures (the room view's own
    /// timeline does that).
    private static var forwardTimelineConfiguration: TimelineConfiguration {
        TimelineConfiguration(
            focus: .live(hideThreadedEvents: true),
            filter: .all,
            internalIdPrefix: nil,
            dateDividerMode: .daily,
            trackReadReceipts: .allEvents,
            reportUtds: false
        )
    }

    // MARK: - Media

    private static func forwardMedia(
        _ msgType: MatrixRustSDK.MessageType,
        client: ClientProtocol,
        timeline: Timeline
    ) async throws {
        guard let media = ForwardMediaSource(msgType) else { return }

        let fileHandle: MediaFileHandle = try await client.getMediaFile(
            mediaSource: media.source,
            filename: media.filename,
            mimeType: media.mimeType ?? "",
            useCache: true,
            tempDir: NSTemporaryDirectory()
        )
        let thumbnail: UploadSource? = await downloadThumbnail(of: media, client: client)
        let filePath: String = try fileHandle.path()
        let params = UploadParameters(
            source: .file(filename: filePath),
            caption: media.caption.map { MessageForwardContent.outgoingText(body: $0).markdown },
            formattedCaption: nil,
            mentions: captionMentions(media.caption),
            inReplyTo: nil
        )

        let handle: SendAttachmentJoinHandle
        switch msgType {
        case let .image(content):
            var info = content.info ?? ImageInfo(
                height: nil, width: nil, mimetype: nil, size: nil,
                thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil
            )
            info.thumbnailSource = nil
            if thumbnail == nil { info.thumbnailInfo = nil }
            handle = try timeline.sendImage(params: params, thumbnailSource: thumbnail, imageInfo: info)
        case let .video(content):
            var info = content.info ?? VideoInfo(
                duration: nil, height: nil, width: nil, mimetype: nil, size: nil,
                thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil
            )
            info.thumbnailSource = nil
            if thumbnail == nil { info.thumbnailInfo = nil }
            handle = try timeline.sendVideo(params: params, thumbnailSource: thumbnail, videoInfo: info)
        case let .audio(content):
            let info = content.info ?? AudioInfo(duration: nil, size: nil, mimetype: nil)
            handle = try timeline.sendAudio(params: params, audioInfo: info)
        case let .file(content):
            var info = content.info ?? FileInfo(mimetype: nil, size: nil, thumbnailInfo: nil, thumbnailSource: nil)
            info.thumbnailSource = nil
            info.thumbnailInfo = nil
            handle = try timeline.sendFile(params: params, fileInfo: info)
        case .text, .notice, .emote, .location, .gallery, .other:
            return
        }
        // The SDK reads the file while it queues the upload, so the handle
        // (and its temp file) must live until the join returns.
        try await handle.join()
        withExtendedLifetime(fileHandle) {}
    }

    /// The thumbnail bytes of an image or video, for the upload. A failed
    /// download only costs the thumbnail: the forward goes on without it.
    private static func downloadThumbnail(of media: ForwardMediaSource, client: ClientProtocol) async -> UploadSource? {
        guard let thumbnailSource = media.thumbnailSource else { return nil }
        do {
            let data: Data = try await client.getMediaContent(mediaSource: thumbnailSource)
            let fileExtension = media.thumbnailMimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension } ?? "jpg"
            return .data(bytes: data, filename: "thumbnail.\(fileExtension)")
        } catch {
            Logger.matrixClient.error("forward: thumbnail download failed: \(error)")
            return nil
        }
    }

    /// The caption's mentions: each pill link in the caption, as the
    /// composer sends them (MATRIX-105).
    private static func captionMentions(_ caption: String?) -> MatrixRustSDK.Mentions? {
        guard let caption else { return nil }
        let userIds = MessageForwardContent.outgoingText(body: caption).mentionedUserIds
        return userIds.isEmpty ? nil : MatrixRustSDK.Mentions(userIds: userIds, room: false)
    }
}

/// The original media message's file and info, for a media forward.
private struct ForwardMediaSource {
    let source: MediaSource
    let filename: String
    let mimeType: String?
    let caption: String?
    /// The thumbnail of an image or video, or nil.
    let thumbnailSource: MediaSource?
    let thumbnailMimeType: String?
}

private extension ForwardMediaSource {
    /// The file facts of a media message, or nil for other content.
    init?(_ msgType: MatrixRustSDK.MessageType) {
        switch msgType {
        case let .image(content):
            self.init(
                source: content.source, filename: content.filename, mimeType: content.info?.mimetype,
                caption: Self.nonBlank(content.caption),
                thumbnailSource: content.info?.thumbnailInfo == nil ? nil : content.info?.thumbnailSource,
                thumbnailMimeType: content.info?.thumbnailInfo?.mimetype
            )
        case let .video(content):
            self.init(
                source: content.source, filename: content.filename, mimeType: content.info?.mimetype,
                caption: Self.nonBlank(content.caption),
                thumbnailSource: content.info?.thumbnailInfo == nil ? nil : content.info?.thumbnailSource,
                thumbnailMimeType: content.info?.thumbnailInfo?.mimetype
            )
        case let .audio(content):
            self.init(
                source: content.source, filename: content.filename, mimeType: content.info?.mimetype,
                caption: Self.nonBlank(content.caption), thumbnailSource: nil, thumbnailMimeType: nil
            )
        case let .file(content):
            self.init(
                source: content.source, filename: content.filename, mimeType: content.info?.mimetype,
                caption: Self.nonBlank(content.caption), thumbnailSource: nil, thumbnailMimeType: nil
            )
        case .text, .notice, .emote, .location, .gallery, .other:
            return nil
        }
    }

    static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }
}
