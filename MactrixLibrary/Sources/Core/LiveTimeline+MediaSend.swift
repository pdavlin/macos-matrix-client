import Foundation
import MatrixRustSDK
import Models
import OSLog

/// Media send for the composer (MATRIX-106).
///
/// `Models.MediaSendRequest` holds every decision (single or gallery, the
/// caption, the info fields). This file only copies those values into the
/// SDK types and calls the SDK send call. It builds no event content.
public extension LiveTimeline {
    /// The SDK refused a media send before it started.
    enum MediaSendError: Error {
        /// The timeline is not loaded yet.
        case timelineUnavailable
    }

    /// Starts a media send and tracks its join handle in `mediaSends`.
    ///
    /// The send queue owns the media from here: the local echo shows the
    /// upload, and a failure shows on the echo with retry and discard.
    ///
    /// - Parameter request: the attachments, the caption, and the reply
    ///   target.
    /// - Returns: the ticket for the send. `mediaSends.cancel(_:)` cancels it.
    /// - Throws: `MediaSendError.timelineUnavailable`, or the SDK error if the
    ///   send could not start (for example, a file the SDK cannot read).
    @discardableResult
    func sendMedia(_ request: MediaSendRequest) throws -> MediaSendTicket {
        guard let timeline else { throw MediaSendError.timelineUnavailable }

        let caption = request.caption?.markdown
        let mentions = request.caption.flatMap { caption in
            caption.mentionedUserIds.isEmpty ? nil : Mentions(userIds: caption.mentionedUserIds, room: false)
        }
        let filenames = request.plan.attachments.map(\.filename)

        switch request.plan {
        case let .single(attachment):
            // formattedCaption nil: the SDK makes the HTML from the caption
            // markdown (to confirm in the dev-account smoke).
            let params = UploadParameters(
                source: attachment.uploadSource,
                caption: caption,
                formattedCaption: nil,
                mentions: mentions,
                inReplyTo: request.inReplyTo
            )
            let handle = try Self.startSingleSend(timeline: timeline, params: params, info: MediaSendInfo(attachment: attachment))
            let ticket = mediaSends.begin(filenames: filenames, isGallery: false) { handle.cancel() }
            Task { [mediaSends] in
                do {
                    try await handle.join()
                } catch {
                    Logger.liveTimeline.error("media send ended with an error: \(error)")
                }
                mediaSends.finish(ticket.id)
            }
            return ticket

        case let .gallery(attachments):
            let params = GalleryUploadParameters(
                caption: caption,
                formattedCaption: nil,
                mentions: mentions,
                inReplyTo: request.inReplyTo
            )
            let itemInfos = attachments.map(Self.galleryItemInfo)
            let handle = try timeline.sendGallery(params: params, itemInfos: itemInfos)
            let ticket = mediaSends.begin(filenames: filenames, isGallery: true) { handle.cancel() }
            Task { [mediaSends] in
                do {
                    try await handle.join()
                } catch {
                    Logger.liveTimeline.error("gallery send ended with an error: \(error)")
                }
                mediaSends.finish(ticket.id)
            }
            return ticket
        }
    }

    /// Cancels the media send that made a local echo: the hook for the
    /// MATRIX-107 cancel button.
    ///
    /// It does two things, because the SDK has two stages:
    ///
    /// 1. It cancels the join handle of the matching ticket
    ///    (`MediaSendTracker.cancel(localEchoTransactionId:filename:)`), if
    ///    the send task still runs.
    /// 2. It aborts the local echo in the send queue through its `SendHandle`
    ///    (the same call as the failed-send Discard), which stops a queued or
    ///    running upload and removes the echo.
    ///
    /// - Parameter localEcho: a local echo media item (its id is a
    ///   transaction id).
    /// - Returns: true if a join handle matched or the send queue aborted the
    ///   echo.
    @discardableResult
    func cancelMediaSend(localEcho: MatrixRustSDK.EventTimelineItem) async -> Bool {
        var cancelled = false
        if case let .transactionId(transactionId) = localEcho.eventOrTransactionId {
            cancelled = mediaSends.cancel(
                localEchoTransactionId: transactionId,
                filename: localEcho.mediaSendFilename
            )
        }
        if let sendHandle = localEcho.lazyProvider.getSendHandle() {
            do {
                let aborted = try await sendHandle.abort()
                cancelled = cancelled || aborted
            } catch {
                Logger.liveTimeline.error("failed to abort media send \(localEcho.eventOrTransactionId.id): \(error)")
            }
        }
        return cancelled
    }

    // MARK: - SDK mapping

    private static func startSingleSend(
        timeline: Timeline,
        params: UploadParameters,
        info: MediaSendInfo
    ) throws -> SendAttachmentJoinHandle {
        let thumbnailSource = info.thumbnail.map { UploadSource.data(bytes: $0.data, filename: $0.filename) }
        switch info.kind {
        case .image:
            return try timeline.sendImage(params: params, thumbnailSource: thumbnailSource, imageInfo: imageInfo(info))
        case .video:
            return try timeline.sendVideo(params: params, thumbnailSource: thumbnailSource, videoInfo: videoInfo(info))
        case .audio:
            return try timeline.sendAudio(params: params, audioInfo: audioInfo(info))
        case .file:
            return try timeline.sendFile(params: params, fileInfo: fileInfo(info))
        }
    }

    private static func galleryItemInfo(_ attachment: ComposerAttachment) -> GalleryItemInfo {
        let info = MediaSendInfo(attachment: attachment)
        let source = attachment.uploadSource
        let thumbnailSource = info.thumbnail.map { UploadSource.data(bytes: $0.data, filename: $0.filename) }
        // The gallery caption is on the gallery, so each item has none.
        switch info.kind {
        case .image:
            return .image(
                imageInfo: imageInfo(info),
                source: source,
                caption: nil,
                formattedCaption: nil,
                thumbnailSource: thumbnailSource
            )
        case .video:
            return .video(
                videoInfo: videoInfo(info),
                source: source,
                caption: nil,
                formattedCaption: nil,
                thumbnailSource: thumbnailSource
            )
        case .audio:
            return .audio(audioInfo: audioInfo(info), source: source, caption: nil, formattedCaption: nil)
        case .file:
            return .file(fileInfo: fileInfo(info), source: source, caption: nil, formattedCaption: nil)
        }
    }

    // `thumbnailSource: MediaSource?` in the info structs is for media that
    // is already uploaded, so it is always nil here. The thumbnail bytes go
    // through the `thumbnailSource: UploadSource?` of the send call.

    private static func thumbnailInfo(_ info: MediaSendInfo) -> ThumbnailInfo? {
        info.thumbnail.map {
            ThumbnailInfo(height: $0.height, width: $0.width, mimetype: $0.mimeType, size: $0.size)
        }
    }

    private static func imageInfo(_ info: MediaSendInfo) -> ImageInfo {
        ImageInfo(
            height: info.height,
            width: info.width,
            mimetype: info.mimeType,
            size: info.size,
            thumbnailInfo: thumbnailInfo(info),
            thumbnailSource: nil,
            blurhash: nil,
            isAnimated: info.isAnimated
        )
    }

    private static func videoInfo(_ info: MediaSendInfo) -> VideoInfo {
        VideoInfo(
            duration: info.duration,
            height: info.height,
            width: info.width,
            mimetype: info.mimeType,
            size: info.size,
            thumbnailInfo: thumbnailInfo(info),
            thumbnailSource: nil,
            blurhash: nil
        )
    }

    private static func audioInfo(_ info: MediaSendInfo) -> AudioInfo {
        AudioInfo(duration: info.duration, size: info.size, mimetype: info.mimeType)
    }

    private static func fileInfo(_ info: MediaSendInfo) -> FileInfo {
        FileInfo(mimetype: info.mimeType, size: info.size, thumbnailInfo: nil, thumbnailSource: nil)
    }
}

extension ComposerAttachment {
    /// The SDK upload source: a file path, or the bytes with the filename.
    var uploadSource: UploadSource {
        switch source {
        case let .file(url):
            .file(filename: url.path(percentEncoded: false))
        case let .data(data):
            .data(bytes: data, filename: filename)
        }
    }
}

extension MatrixRustSDK.EventTimelineItem {
    /// The filename in a single media message, for the cancel match. Nil for
    /// a gallery and for other content.
    var mediaSendFilename: String? {
        guard case let .msgLike(content: msgLike) = content, case let .message(content: message) = msgLike.kind else {
            return nil
        }
        switch message.msgType {
        case let .image(content: content): return content.filename
        case let .video(content: content): return content.filename
        case let .audio(content: content): return content.filename
        case let .file(content: content): return content.filename
        default: return nil
        }
    }
}
