import Foundation
import Models
import Utils

/// Measures a pending composer attachment before send (MATRIX-106).
///
/// It joins the probes in `Utils.MediaProbe` (ImageIO, AVFoundation) with the
/// rules in `Models.MediaThumbnailPolicy`. A probe that fails gives empty
/// values, not an error: the media still sends, with fewer info fields.
public enum MediaAttachmentMeasurer {
    /// - Parameter attachment: the attachment to measure.
    /// - Returns: the values for its kind. `.empty` for a file.
    public static func measure(_ attachment: ComposerAttachment) async -> MediaMeasurement {
        switch attachment.kind {
        case .image:
            return measureImage(attachment)
        case .video:
            guard case let .file(url) = attachment.source else { return .empty }
            return await measureVideo(at: url)
        case .audio:
            guard case let .file(url) = attachment.source else { return .empty }
            return await MediaMeasurement(duration: MediaProbe.probeAudioDuration(at: url))
        case .file:
            return .empty
        }
    }

    private static func measureImage(_ attachment: ComposerAttachment) -> MediaMeasurement {
        let probe: ImageProbe? = switch attachment.source {
        case let .file(url): MediaProbe.probeImage(at: url)
        case let .data(data): MediaProbe.probeImage(data: data)
        }
        guard let probe else { return .empty }

        let width = UInt64(probe.width)
        let height = UInt64(probe.height)
        let isAnimated = probe.frameCount > 1
        var measurement = MediaMeasurement(width: width, height: height, isAnimated: isAnimated)

        let wantsThumbnail = MediaThumbnailPolicy.shouldThumbnailImage(
            width: width,
            height: height,
            byteCount: attachment.byteCount,
            isAnimated: isAnimated
        )
        if wantsThumbnail {
            measurement.thumbnail = imageThumbnail(attachment.source, maxPixelSize: MediaThumbnailPolicy.maxPixelSize)
        }
        measurement.preview = imageThumbnail(attachment.source, maxPixelSize: MediaThumbnailPolicy.previewMaxPixelSize)
        return measurement
    }

    private static func imageThumbnail(_ source: ComposerAttachment.Source, maxPixelSize: Int) -> MediaThumbnail? {
        let encoded: EncodedThumbnail? = switch source {
        case let .file(url):
            MediaProbe.imageThumbnail(at: url, maxPixelSize: maxPixelSize, jpegQuality: MediaThumbnailPolicy.jpegQuality)
        case let .data(data):
            MediaProbe.imageThumbnail(data: data, maxPixelSize: maxPixelSize, jpegQuality: MediaThumbnailPolicy.jpegQuality)
        }
        return encoded.map(mediaThumbnail)
    }

    private static func measureVideo(at url: URL) async -> MediaMeasurement {
        guard let probe = await MediaProbe.probeVideo(
            at: url,
            maxPixelSize: MediaThumbnailPolicy.maxPixelSize,
            jpegQuality: MediaThumbnailPolicy.jpegQuality
        ) else { return .empty }
        return MediaMeasurement(
            width: probe.width.map(UInt64.init),
            height: probe.height.map(UInt64.init),
            duration: probe.duration,
            thumbnail: probe.poster.map(mediaThumbnail),
            preview: probe.poster.map(mediaThumbnail)
        )
    }

    private static func mediaThumbnail(_ encoded: EncodedThumbnail) -> MediaThumbnail {
        MediaThumbnail(
            data: encoded.data,
            width: UInt64(encoded.width),
            height: UInt64(encoded.height),
            mimeType: encoded.mimeType
        )
    }
}
