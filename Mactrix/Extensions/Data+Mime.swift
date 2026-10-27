import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension Data {
    func computeMimeType() -> UTType? {
        guard let b: UInt8 = first else { return nil }

        switch b {
        case 0xff:
            return .jpeg
        case 0x89:
            return .png
        case 0x47:
            return .gif
        case 0x4d, 0x49:
            return .tiff
        case 0x25:
            return .pdf
        case 0x46:
            return .plainText
        case 0x52:
            return .webP
        default:
            return nil
        }
    }

    /// Decode image data into an NSImage, applying EXIF orientation.
    /// `Image(importing:contentType:)` on macOS does not apply EXIF orientation,
    /// so we let ImageIO bake the orientation into a full-size CGImage at decode
    /// time. A lazy `NSCIImageRep` re-rendered through CoreImage on every draw
    /// and crashed in CoreImage's program compiler (MATRIX-79).
    struct ImageDecodeError: Error {}

    func toOrientedImage(contentType _: UTType? = nil) throws -> NSImage {
        // No kCGImageSourceThumbnailMaxPixelSize: the "thumbnail" is full size.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard
            let source = CGImageSourceCreateWithData(self as CFData, nil),
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else {
            throw ImageDecodeError()
        }

        return NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
    }
}
