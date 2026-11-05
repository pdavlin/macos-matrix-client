import Foundation
import UniformTypeIdentifiers

/// The Matrix message type a composer attachment is sent as (MATRIX-106).
///
/// Each kind maps to one SDK send call: `sendImage`, `sendVideo`,
/// `sendAudio`, or `sendFile`. In a gallery, each kind maps to one
/// `GalleryItemInfo` case.
public enum MediaSendKind: String, Equatable, Hashable, Sendable, CaseIterable {
    case image
    case video
    case audio
    case file

    /// The image types that Matrix clients show inline. Other images (HEIC,
    /// TIFF, PSD, SVG) go as files, because many clients cannot show them.
    public static let inlineImageTypes: [UTType] = [.jpeg, .png, .gif, .webP]

    /// The video containers that Matrix clients play inline. Other movies
    /// (AVI, MKV) go as files.
    public static let inlineVideoTypes: [UTType] = [.mpeg4Movie, .quickTimeMovie]
        + [UTType("com.apple.m4v-video")].compactMap(\.self)

    /// The kind for a content type.
    ///
    /// - Parameter contentType: the attachment type, for example from the file
    ///   extension. Nil (an unknown type) gives `.file`.
    /// - Returns: `.image` for an inline image type, `.video` for an inline
    ///   video type, `.audio` for any audio type, and `.file` for all others.
    public init(contentType: UTType?) {
        guard let contentType else {
            self = .file
            return
        }
        if Self.inlineImageTypes.contains(where: { contentType.conforms(to: $0) }) {
            self = .image
        } else if Self.inlineVideoTypes.contains(where: { contentType.conforms(to: $0) }) {
            self = .video
        } else if contentType.conforms(to: .audio) {
            self = .audio
        } else {
            self = .file
        }
    }
}

/// A thumbnail the app made for an attachment: JPEG data and its pixel size.
public struct MediaThumbnail: Equatable, Sendable {
    public let data: Data
    public let width: UInt64
    public let height: UInt64
    public let mimeType: String

    public init(data: Data, width: UInt64, height: UInt64, mimeType: String) {
        self.data = data
        self.width = width
        self.height = height
        self.mimeType = mimeType
    }

    /// The byte count of `data`.
    public var size: UInt64 {
        UInt64(data.count)
    }
}

/// The values the app measured for an attachment (ImageIO for images,
/// AVFoundation for video and audio). Each value is nil if it is unknown.
public struct MediaMeasurement: Equatable, Sendable {
    /// Pixel width after the orientation is applied.
    public var width: UInt64?
    /// Pixel height after the orientation is applied.
    public var height: UInt64?
    /// The play time of a video or audio file, in seconds.
    public var duration: TimeInterval?
    /// True for an image with more than one frame (an animated GIF).
    public var isAnimated: Bool?
    /// The thumbnail to upload with the media, or nil for none.
    public var thumbnail: MediaThumbnail?
    /// A small image for the composer chip only. It is never sent.
    public var preview: MediaThumbnail?

    public init(
        width: UInt64? = nil,
        height: UInt64? = nil,
        duration: TimeInterval? = nil,
        isAnimated: Bool? = nil,
        thumbnail: MediaThumbnail? = nil,
        preview: MediaThumbnail? = nil
    ) {
        self.width = width
        self.height = height
        self.duration = duration
        self.isAnimated = isAnimated
        self.thumbnail = thumbnail
        self.preview = preview
    }

    /// No measured values: for a file, or when a measurement failed.
    public static let empty = MediaMeasurement()
}

/// One pending attachment in the composer (MATRIX-106).
///
/// The composer shows it as a chip above the text field. On send it becomes
/// an `UploadSource` and an info struct for the SDK.
public struct ComposerAttachment: Identifiable, Equatable, Sendable {
    /// Where the bytes come from.
    public enum Source: Equatable, Sendable {
        /// A file on disk (file picker, drop, pasted file URL). The SDK reads
        /// it through `UploadSource.file(filename:)`.
        case file(URL)
        /// Bytes in memory (a pasted image). The SDK reads them through
        /// `UploadSource.data(bytes:filename:)`.
        case data(Data)
    }

    public let id: UUID
    public let source: Source
    /// The name the recipient sees, with the extension.
    public let filename: String
    public let kind: MediaSendKind
    /// The MIME type from UniformTypeIdentifiers, or nil if it is unknown.
    public let mimeType: String?
    /// The byte count, or nil if it is unknown.
    public let byteCount: UInt64?
    /// The measured values, or nil while the measurement runs.
    public var measurement: MediaMeasurement?

    public init(
        id: UUID = UUID(),
        source: Source,
        filename: String,
        kind: MediaSendKind,
        mimeType: String?,
        byteCount: UInt64?,
        measurement: MediaMeasurement? = nil
    ) {
        self.id = id
        self.source = source
        self.filename = filename
        self.kind = kind
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.measurement = measurement
    }

    /// Makes an attachment for a file on disk. The kind and the MIME type
    /// come from the file extension.
    ///
    /// - Parameters:
    ///   - url: the file URL.
    ///   - byteCount: the file size, or nil if it is unknown.
    /// - Returns: an attachment with no measurement yet.
    public static func file(at url: URL, byteCount: UInt64?) -> ComposerAttachment {
        let contentType = UTType(filenameExtension: url.pathExtension)
        return ComposerAttachment(
            source: .file(url),
            filename: url.lastPathComponent,
            kind: MediaSendKind(contentType: contentType),
            mimeType: contentType?.preferredMIMEType,
            byteCount: byteCount
        )
    }

    /// Makes an attachment for image bytes from the pasteboard.
    ///
    /// - Parameters:
    ///   - data: the encoded image.
    ///   - contentType: the image type of `data`.
    ///   - filename: the name to send, with the extension.
    /// - Returns: an attachment with no measurement yet.
    public static func imageData(_ data: Data, contentType: UTType, filename: String) -> ComposerAttachment {
        ComposerAttachment(
            source: .data(data),
            filename: filename,
            kind: MediaSendKind(contentType: contentType),
            mimeType: contentType.preferredMIMEType,
            byteCount: UInt64(data.count)
        )
    }

    /// True when the measurement finished, so the attachment can be sent.
    public var isReady: Bool {
        measurement != nil
    }
}

/// When the app makes a thumbnail for an attachment (MATRIX-106).
public enum MediaThumbnailPolicy {
    /// The longest side of a thumbnail, in pixels.
    public static let maxPixelSize = 800

    /// The longest side of a composer chip preview, in pixels.
    public static let previewMaxPixelSize = 160

    /// An image with fewer bytes than this and no side over `maxPixelSize`
    /// is sent with no thumbnail: clients show the image itself.
    public static let imageByteThreshold: UInt64 = 1_000_000

    /// The JPEG quality for thumbnails, from 0 to 1. A source with
    /// transparency gets a PNG thumbnail instead, because JPEG has no alpha.
    public static let jpegQuality = 0.8

    /// The upload filename of a thumbnail.
    ///
    /// - Parameter mimeType: the thumbnail type.
    /// - Returns: `thumbnail.png` for PNG, else `thumbnail.jpg`.
    public static func filename(forMimeType mimeType: String) -> String {
        mimeType == "image/png" ? "thumbnail.png" : "thumbnail.jpg"
    }

    /// Whether to make a thumbnail for an image.
    ///
    /// - Parameters:
    ///   - width: the pixel width, or nil if it is unknown.
    ///   - height: the pixel height, or nil if it is unknown.
    ///   - byteCount: the file size, or nil if it is unknown.
    ///   - isAnimated: true for an animated image. A still thumbnail would
    ///     stop the animation in clients that show the thumbnail, so an
    ///     animated image gets none.
    /// - Returns: true for a large still image.
    public static func shouldThumbnailImage(
        width: UInt64?,
        height: UInt64?,
        byteCount: UInt64?,
        isAnimated: Bool
    ) -> Bool {
        guard !isAnimated else { return false }
        let longestSide = max(width ?? 0, height ?? 0)
        return longestSide > UInt64(maxPixelSize) || (byteCount ?? 0) > imageByteThreshold
    }
}

/// Picks the image type to read from the pasteboard and names the pasted
/// file (MATRIX-106).
public enum PastedImage {
    /// The image types the composer reads from the pasteboard, best first.
    /// TIFF is last because it is large and clients cannot show it: the app
    /// converts it to PNG (`convertsToPNG`).
    public static let readableTypes: [UTType] = [.png, .jpeg, .gif, .tiff]

    /// The type to read from the types the pasteboard has.
    ///
    /// - Parameter available: the types on the pasteboard, in pasteboard
    ///   order.
    /// - Returns: the available type that conforms to the best of
    ///   `readableTypes`, or nil if none conforms.
    public static func preferredType(from available: [UTType]) -> UTType? {
        for readable in readableTypes {
            if let match = available.first(where: { $0.conforms(to: readable) }) {
                return match
            }
        }
        return nil
    }

    /// Whether the app converts this pasted type to PNG before send.
    public static func convertsToPNG(_ type: UTType) -> Bool {
        type.conforms(to: .tiff)
    }

    /// The filename for a pasted image, for example
    /// `Pasted image 2026-11-04 at 15.45.20.png`.
    ///
    /// - Parameters:
    ///   - date: the paste time.
    ///   - contentType: the type of the bytes to send.
    ///   - timeZone: the time zone for the date and time. Tests set it.
    /// - Returns: a name with the extension for `contentType`.
    public static func filename(date: Date, contentType: UTType, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(
            format: "%04d-%02d-%02d at %02d.%02d.%02d",
            parts.year ?? 0, parts.month ?? 0, parts.day ?? 0,
            parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
        )
        let fileExtension = contentType.preferredFilenameExtension ?? "png"
        return "Pasted image \(stamp).\(fileExtension)"
    }
}

/// What a paste or a drop into the composer does (MATRIX-106).
///
/// The text view reports what the pasteboard holds, and this picks the
/// action. Text wins when the pasteboard has text and an image (an app that
/// copies text often adds a picture of it), except when it has file URLs:
/// a file copied in Finder has its name as text too.
public enum ComposerPasteDecision: Equatable, Sendable {
    /// Let the text view paste as usual (text, or composer draft text with
    /// mention chips).
    case text
    /// Add the file URLs as attachments.
    case attachFiles
    /// Add the image data as one attachment.
    case attachImage

    /// - Parameters:
    ///   - hasDraftText: the pasteboard has composer draft text (a copy from
    ///     a composer, with chips).
    ///   - fileURLCount: the number of file URLs on the pasteboard.
    ///   - hasImageData: the pasteboard has a readable image type
    ///     (`PastedImage.readableTypes`).
    ///   - hasText: the pasteboard has plain or rich text.
    /// - Returns: the action for the paste or the drop.
    public static func decide(
        hasDraftText: Bool,
        fileURLCount: Int,
        hasImageData: Bool,
        hasText: Bool
    ) -> ComposerPasteDecision {
        if hasDraftText { return .text }
        if fileURLCount > 0 { return .attachFiles }
        if hasImageData, !hasText { return .attachImage }
        return .text
    }
}
