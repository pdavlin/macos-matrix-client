import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The pixel size and frame count of an image, from ImageIO.
public struct ImageProbe: Equatable, Sendable {
    /// Pixel width after the EXIF orientation is applied.
    public let width: Int
    /// Pixel height after the EXIF orientation is applied.
    public let height: Int
    /// More than 1 for an animated image.
    public let frameCount: Int

    public init(width: Int, height: Int, frameCount: Int) {
        self.width = width
        self.height = height
        self.frameCount = frameCount
    }
}

/// An encoded thumbnail image and its pixel size.
public struct EncodedThumbnail: Equatable, Sendable {
    public let data: Data
    public let width: Int
    public let height: Int
    /// `image/jpeg`, or `image/png` for a source with transparency.
    public let mimeType: String

    public init(data: Data, width: Int, height: Int, mimeType: String) {
        self.data = data
        self.width = width
        self.height = height
        self.mimeType = mimeType
    }
}

/// The values of a video, from AVFoundation.
public struct VideoProbe: Equatable, Sendable {
    /// The play time in seconds.
    public let duration: TimeInterval
    /// The display width, after the track transform (a portrait phone video
    /// is taller than wide).
    public let width: Int?
    /// The display height, after the track transform.
    public let height: Int?
    /// A frame from the start of the video, or nil if AVFoundation could not
    /// make one.
    public let poster: EncodedThumbnail?
}

/// Measures media for the composer before send (MATRIX-106).
///
/// Images use ImageIO only (never CoreImage, see MATRIX-79). Video and audio
/// use AVFoundation (`AVURLAsset`, `AVAssetImageGenerator`). All of these
/// frameworks are on macOS and iOS.
public enum MediaProbe {
    // MARK: - Images

    /// Reads the size and frame count of an image file.
    ///
    /// - Parameter url: the file URL.
    /// - Returns: nil if ImageIO cannot read the file as an image.
    public static func probeImage(at url: URL) -> ImageProbe? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return probeImage(source: source)
    }

    /// Reads the size and frame count of encoded image bytes.
    ///
    /// - Parameter data: the encoded image.
    /// - Returns: nil if ImageIO cannot read the bytes as an image.
    public static func probeImage(data: Data) -> ImageProbe? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return probeImage(source: source)
    }

    /// Makes a thumbnail of an image file.
    ///
    /// - Parameters:
    ///   - url: the file URL.
    ///   - maxPixelSize: the longest side of the thumbnail.
    ///   - jpegQuality: the JPEG quality, from 0 to 1.
    /// - Returns: nil if ImageIO cannot decode or encode the image.
    public static func imageThumbnail(at url: URL, maxPixelSize: Int, jpegQuality: Double) -> EncodedThumbnail? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source: source, maxPixelSize: maxPixelSize, jpegQuality: jpegQuality)
    }

    /// Makes a thumbnail of encoded image bytes.
    ///
    /// - Parameters:
    ///   - data: the encoded image.
    ///   - maxPixelSize: the longest side of the thumbnail.
    ///   - jpegQuality: the JPEG quality, from 0 to 1.
    /// - Returns: nil if ImageIO cannot decode or encode the image.
    public static func imageThumbnail(data: Data, maxPixelSize: Int, jpegQuality: Double) -> EncodedThumbnail? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(source: source, maxPixelSize: maxPixelSize, jpegQuality: jpegQuality)
    }

    /// Converts encoded image bytes (for example a pasted TIFF) to PNG.
    ///
    /// - Parameter data: the encoded image.
    /// - Returns: the first frame as PNG, or nil if ImageIO cannot convert it.
    public static func pngData(fromImageData data: Data) -> Data? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        return encode(image, as: .png, properties: properties.map(orientationOnly) ?? [:])
    }

    // MARK: - Video and audio

    /// Reads the duration, the display size, and a poster frame of a video.
    ///
    /// - Parameters:
    ///   - url: the file URL.
    ///   - maxPixelSize: the longest side of the poster.
    ///   - jpegQuality: the poster JPEG quality, from 0 to 1.
    /// - Returns: nil if AVFoundation cannot read the duration.
    public static func probeVideo(at url: URL, maxPixelSize: Int, jpegQuality: Double) async -> VideoProbe? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }

        var width: Int?
        var height: Int?
        let track = try? await asset.loadTracks(withMediaType: .video).first
        if let (naturalSize, transform) = try? await track?.load(.naturalSize, .preferredTransform) {
            let displaySize = naturalSize.applying(transform)
            width = Int(abs(displaySize.width).rounded())
            height = Int(abs(displaySize.height).rounded())
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        var poster: EncodedThumbnail?
        if let (frame, _) = try? await generator.image(at: .zero) {
            poster = encodeThumbnail(frame, jpegQuality: jpegQuality)
        }

        return VideoProbe(duration: duration.seconds, width: width, height: height, poster: poster)
    }

    /// Reads the duration of an audio file.
    ///
    /// - Parameter url: the file URL.
    /// - Returns: the play time in seconds, or nil if AVFoundation cannot
    ///   read it.
    public static func probeAudioDuration(at url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration), duration.isNumeric else { return nil }
        return duration.seconds
    }

    // MARK: - Private

    private static func probeImage(source: CGImageSource) -> ImageProbe? {
        let frameCount = CGImageSourceGetCount(source)
        guard
            frameCount > 0,
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
            let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }

        // EXIF orientations 5 to 8 turn the image by 90 degrees.
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let isTurned = (5 ... 8).contains(orientation)
        return ImageProbe(
            width: isTurned ? pixelHeight : pixelWidth,
            height: isTurned ? pixelWidth : pixelHeight,
            frameCount: frameCount
        )
    }

    private static func thumbnail(source: CGImageSource, maxPixelSize: Int, jpegQuality: Double) -> EncodedThumbnail? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return encodeThumbnail(image, jpegQuality: jpegQuality)
    }

    /// Encodes a thumbnail as JPEG, or as PNG if the image has transparency.
    private static func encodeThumbnail(_ image: CGImage, jpegQuality: Double) -> EncodedThumbnail? {
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let type: UTType = hasAlpha ? .png : .jpeg
        let properties: [CFString: Any] = hasAlpha ? [:] : [kCGImageDestinationLossyCompressionQuality: jpegQuality]
        guard let data = encode(image, as: type, properties: properties), let mimeType = type.preferredMIMEType else {
            return nil
        }
        return EncodedThumbnail(data: data, width: image.width, height: image.height, mimeType: mimeType)
    }

    private static func encode(_ image: CGImage, as type: UTType, properties: [CFString: Any]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Keeps the EXIF orientation of a converted image, so it shows the same
    /// way up as the source.
    private static func orientationOnly(_ properties: [CFString: Any]) -> [CFString: Any] {
        guard let orientation = properties[kCGImagePropertyOrientation] else { return [:] }
        return [kCGImagePropertyOrientation: orientation]
    }
}
