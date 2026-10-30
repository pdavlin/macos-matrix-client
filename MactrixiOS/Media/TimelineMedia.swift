import CoreGraphics
import Foundation
import MatrixRustSDK
import UI

/// One media message, reduced to what the iOS media rows draw and fetch
/// (MATRIX-86). SDK rows map into it; the DEBUG fixture builds it directly.
struct TimelineMedia {
    enum Kind: Equatable {
        case image
        case video
        case audio
        case file

        /// Images and videos draw an inline thumbnail box; audio and files
        /// draw an attachment row.
        var isVisual: Bool {
            self == .image || self == .video
        }

        /// What the viewer can save to the photo library.
        var canSaveToPhotos: Bool {
            isVisual
        }

        var systemImage: String {
            switch self {
            case .image: "photo"
            case .video: "film"
            case .audio: "waveform"
            case .file: "doc"
            }
        }
    }

    let kind: Kind
    let filename: String
    let caption: String?
    let mimeType: String?
    let byteSize: UInt64?
    let duration: TimeInterval?
    let width: UInt64?
    let height: UInt64?
    /// The full media. Nil for fixture media.
    let source: MatrixRustSDK.MediaSource?
    /// What the inline box shows: the event's thumbnail, or for an image
    /// without one, the image itself. Nil when there is nothing to show.
    let previewSource: MatrixRustSDK.MediaSource?
    /// Identity of the preview for the decoded-image cache.
    let previewKey: String?

    /// The detail line of an attachment row: duration, then size.
    var subtitle: String? {
        var parts: [String] = []
        if let duration {
            parts.append(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
        }
        if let byteSize {
            parts.append(Int64(clamping: byteSize).formatted(.byteCount(style: .file)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension TimelineMedia {
    /// The media an SDK message type draws, or nil for a non-media type. The
    /// switch is exhaustive so a new SDK case has to be placed here.
    init?(_ type: MatrixRustSDK.MessageType) {
        switch type {
        case let .image(content):
            let preview = content.info?.thumbnailSource ?? content.source
            self.init(
                kind: .image,
                filename: content.filename,
                caption: content.caption,
                mimeType: content.info?.mimetype,
                byteSize: content.info?.size,
                duration: nil,
                width: content.info?.width,
                height: content.info?.height,
                source: content.source,
                previewSource: preview,
                previewKey: preview.url()
            )
        case let .video(content):
            let preview = content.info?.thumbnailSource
            self.init(
                kind: .video,
                filename: content.filename,
                caption: content.caption,
                mimeType: content.info?.mimetype,
                byteSize: content.info?.size,
                duration: content.info?.duration,
                width: content.info?.width,
                height: content.info?.height,
                source: content.source,
                previewSource: preview,
                previewKey: preview?.url()
            )
        case let .audio(content):
            self.init(
                kind: .audio,
                filename: content.filename,
                caption: content.caption,
                mimeType: content.info?.mimetype,
                byteSize: content.info?.size,
                duration: content.info?.duration,
                width: nil,
                height: nil,
                source: content.source,
                previewSource: nil,
                previewKey: nil
            )
        case let .file(content):
            self.init(
                kind: .file,
                filename: content.filename,
                caption: content.caption,
                mimeType: content.info?.mimetype,
                byteSize: content.info?.size,
                duration: nil,
                width: nil,
                height: nil,
                source: content.source,
                previewSource: nil,
                previewKey: nil
            )
        case .text, .notice, .emote, .gallery, .location, .other:
            return nil
        }
    }
}

/// The size of an inline image or video box (MATRIX-86).
///
/// A pure function of the proposed width and the event's media info, never
/// of the loaded pixels, so the offscreen measurement and the cell agree
/// before and after the thumbnail arrives. The info is in the height
/// fingerprint, so the cache re-measures when it changes.
enum MediaBoxGeometry {
    /// The shape assumed when the event carries no dimensions.
    static let fallbackAspectRatio: CGFloat = 4.0 / 3.0

    static func size(proposedWidth: CGFloat, mediaWidth: UInt64?, mediaHeight: UInt64?) -> CGSize {
        let ratio = MediaRowLayout.aspectRatio(width: mediaWidth, height: mediaHeight) ?? fallbackAspectRatio
        let maxHeight = MediaRowLayout.maxHeight(height: mediaHeight)
        let width = floor(max(0, min(proposedWidth, maxHeight * ratio)))
        return CGSize(width: width, height: floor(width / ratio))
    }
}

/// Fetches media for the rows and the viewer (MATRIX-86).
@MainActor
protocol TimelineMediaLoading {
    /// The encoded preview image for an image or video box.
    func previewData(for media: TimelineMedia) async throws -> Data
    /// The media as a local file for the viewer.
    func download(_ media: TimelineMedia) async throws -> MediaViewerItem
}
