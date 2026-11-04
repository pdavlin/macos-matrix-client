import Foundation
import ImageIO
import UIKit

/// Decodes inline media previews on iOS (MATRIX-86).
///
/// ImageIO only: `CGImageSourceCreateThumbnailAtIndex` downsamples while it
/// decodes, and `kCGImageSourceCreateThumbnailWithTransform` applies the EXIF
/// orientation. No CoreImage: the `CIImage` decode path crashed the Mac app
/// (MATRIX-79).
enum MediaThumbnailDecoder {
    struct DecodeError: LocalizedError {
        var errorDescription: String? {
            "The media data is not an image."
        }
    }

    /// The longest side, in pixels, of a decoded preview. The inline box is
    /// at most `BubbleToken.mediaMaxHeight` points tall, so this covers a 3x
    /// screen with room to spare and keeps a large photo out of memory.
    static let maxPixelSize = 1200

    /// Decodes `data` into an oriented image whose longest side is at most
    /// `maxPixelSize` pixels.
    static func thumbnail(from data: Data, maxPixelSize: Int = maxPixelSize) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw DecodeError()
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw DecodeError()
        }
        return image
    }

    /// Decodes off the main actor, on a utility-priority task.
    static func decode(_ data: Data) async throws -> UIImage {
        try await Task.detached(priority: .utility) {
            try UIImage(cgImage: thumbnail(from: data))
        }.value
    }
}
