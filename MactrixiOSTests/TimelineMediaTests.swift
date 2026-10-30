import ImageIO
@testable import MactrixiOS
import Tokens
import UIKit
import XCTest

/// MATRIX-86: media kinds, box geometry, attachment subtitles, and the
/// ImageIO preview decode.
final class TimelineMediaTests: XCTestCase {
    private func media(
        _ kind: TimelineMedia.Kind,
        byteSize: UInt64? = nil,
        duration: TimeInterval? = nil
    ) -> TimelineMedia {
        TimelineMedia(
            kind: kind,
            filename: "file",
            caption: nil,
            mimeType: nil,
            byteSize: byteSize,
            duration: duration,
            width: nil,
            height: nil,
            source: nil,
            previewSource: nil,
            previewKey: nil
        )
    }

    func testOnlyImagesAndVideosAreVisualAndSaveToPhotos() {
        XCTAssertTrue(TimelineMedia.Kind.image.isVisual)
        XCTAssertTrue(TimelineMedia.Kind.video.isVisual)
        XCTAssertFalse(TimelineMedia.Kind.audio.isVisual)
        XCTAssertFalse(TimelineMedia.Kind.file.isVisual)
        XCTAssertTrue(TimelineMedia.Kind.image.canSaveToPhotos)
        XCTAssertTrue(TimelineMedia.Kind.video.canSaveToPhotos)
        XCTAssertFalse(TimelineMedia.Kind.audio.canSaveToPhotos)
        XCTAssertFalse(TimelineMedia.Kind.file.canSaveToPhotos)
    }

    func testBoxFillsWidthAtTheMediaAspectRatio() {
        // 4:3 and 300pt tall at most: a 320pt column is the limit.
        let size = MediaBoxGeometry.size(proposedWidth: 320, mediaWidth: 4000, mediaHeight: 3000)
        XCTAssertEqual(size, CGSize(width: 320, height: 240))
    }

    func testBoxCapsTallMediaAtTheTokenHeight() {
        let size = MediaBoxGeometry.size(proposedWidth: 390, mediaWidth: 1000, mediaHeight: 2000)
        XCTAssertEqual(size.height, BubbleToken.mediaMaxHeight)
        XCTAssertEqual(size.width, BubbleToken.mediaMaxHeight / 2)
    }

    func testBoxNeverUpscalesPastThePixelHeight() {
        let size = MediaBoxGeometry.size(proposedWidth: 390, mediaWidth: 200, mediaHeight: 100)
        XCTAssertEqual(size, CGSize(width: 200, height: 100))
    }

    func testBoxWithoutDimensionsUsesTheFallbackShape() {
        let size = MediaBoxGeometry.size(proposedWidth: 300, mediaWidth: nil, mediaHeight: nil)
        XCTAssertEqual(size, CGSize(width: 300, height: 225))
    }

    func testBoxDependsOnlyOnWidthAndInfo() {
        let first = MediaBoxGeometry.size(proposedWidth: 333.5, mediaWidth: 1920, mediaHeight: 1080)
        let second = MediaBoxGeometry.size(proposedWidth: 333.5, mediaWidth: 1920, mediaHeight: 1080)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.width, first.width.rounded(.down))
        XCTAssertEqual(first.height, first.height.rounded(.down))
    }

    func testSubtitleJoinsDurationAndSize() {
        XCTAssertNil(media(.file).subtitle)
        XCTAssertEqual(media(.audio, duration: 75).subtitle, "1:15")
        let both = media(.audio, byteSize: 2048, duration: 5).subtitle
        XCTAssertEqual(both?.hasPrefix("0:05 · "), true)
    }

    func testDecoderAppliesOrientationAndDownsamples() throws {
        // A 40 by 20 image tagged "rotated 90°" (EXIF 6) decodes upright, as 20 by 40.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cgImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let decoded = try MediaThumbnailDecoder.thumbnail(from: data as Data, maxPixelSize: 1000)
        XCTAssertEqual(decoded.width, 20)
        XCTAssertEqual(decoded.height, 40)

        let small = try MediaThumbnailDecoder.thumbnail(from: data as Data, maxPixelSize: 10)
        XCTAssertLessThanOrEqual(max(small.width, small.height), 10)
    }

    func testDecoderRejectsNonImageData() {
        XCTAssertThrowsError(try MediaThumbnailDecoder.thumbnail(from: Data("not an image".utf8)))
    }
}
