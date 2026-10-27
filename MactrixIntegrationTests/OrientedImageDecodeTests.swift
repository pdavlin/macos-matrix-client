import AppKit
import ImageIO
@testable import Mactrix
import UniformTypeIdentifiers
import XCTest

/// MATRIX-79: `toOrientedImage` must keep applying EXIF orientation (#66)
/// after moving from a lazy `NSCIImageRep` to an ImageIO-decoded CGImage.
final class OrientedImageDecodeTests: XCTestCase {
    private let pixelWidth = 4
    private let pixelHeight = 2

    /// Encode a 4x2 JPEG that carries the given EXIF orientation tag.
    private func makeJPEG(orientation: CGImagePropertyOrientation) throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        let cgImage = try XCTUnwrap(context.makeImage())

        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data as CFMutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation.rawValue]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func decodedPixelSize(_ image: NSImage) throws -> CGSize {
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    func testUpOrientationKeepsDimensions() throws {
        let image = try makeJPEG(orientation: .up).toOrientedImage()

        XCTAssertEqual(image.size, CGSize(width: pixelWidth, height: pixelHeight))
        XCTAssertEqual(try decodedPixelSize(image), CGSize(width: pixelWidth, height: pixelHeight))
    }

    func testRightOrientationSwapsDimensions() throws {
        let image = try makeJPEG(orientation: .right).toOrientedImage()

        XCTAssertEqual(image.size, CGSize(width: pixelHeight, height: pixelWidth))
        XCTAssertEqual(try decodedPixelSize(image), CGSize(width: pixelHeight, height: pixelWidth))
    }

    func testDecodedImageHasNoCoreImageRepresentation() throws {
        let image = try makeJPEG(orientation: .right).toOrientedImage()

        XCTAssertFalse(image.representations.contains { $0 is NSCIImageRep })
    }

    func testInvalidDataThrows() {
        XCTAssertThrowsError(try Data([0x00, 0x01, 0x02]).toOrientedImage())
    }
}
