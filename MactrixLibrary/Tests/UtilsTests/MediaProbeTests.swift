import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Utils

/// MATRIX-106: image measurement with ImageIO and video measurement with
/// AVFoundation. Every fixture is made in code and is a few KB.
struct MediaProbeImageTests {
    /// Draws a solid image and encodes it.
    private func encodedImage(
        width: Int,
        height: Int,
        type: UTType,
        opaque: Bool = true,
        orientation: Int? = nil,
        frames: Int = 1
    ) -> Data {
        let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: alpha.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: opaque ? 1 : 0.5)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, frames, nil)!
        var properties: [CFString: Any] = [:]
        if let orientation {
            properties[kCGImagePropertyOrientation] = orientation
        }
        for _ in 0 ..< frames {
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test func probeReadsThePixelSize() throws {
        let probe = try #require(MediaProbe.probeImage(data: encodedImage(width: 120, height: 80, type: .png)))
        #expect(probe == ImageProbe(width: 120, height: 80, frameCount: 1))
    }

    @Test func probeAppliesATurningOrientation() throws {
        // EXIF 6: turned 90 degrees, so the shown image is 80 wide, 120 tall.
        let data = encodedImage(width: 120, height: 80, type: .jpeg, orientation: 6)
        let probe = try #require(MediaProbe.probeImage(data: data))
        #expect(probe.width == 80)
        #expect(probe.height == 120)
    }

    @Test func probeCountsGifFrames() throws {
        let probe = try #require(MediaProbe.probeImage(data: encodedImage(width: 16, height: 16, type: .gif, frames: 2)))
        #expect(probe.frameCount == 2)
    }

    @Test func probeReadsAFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).png")
        try encodedImage(width: 30, height: 20, type: .png).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(MediaProbe.probeImage(at: url) == ImageProbe(width: 30, height: 20, frameCount: 1))
    }

    @Test func probeRejectsNonImageBytes() {
        #expect(MediaProbe.probeImage(data: Data("not an image".utf8)) == nil)
    }

    @Test func opaqueThumbnailIsAJpegInsideTheMaxSize() throws {
        let data = encodedImage(width: 1600, height: 900, type: .png)
        let thumbnail = try #require(MediaProbe.imageThumbnail(data: data, maxPixelSize: 400, jpegQuality: 0.8))
        #expect(thumbnail.mimeType == "image/jpeg")
        #expect(thumbnail.width == 400)
        #expect(thumbnail.height == 225)
        #expect(MediaProbe.probeImage(data: thumbnail.data)?.width == 400)
    }

    @Test func transparentThumbnailIsAPng() throws {
        let data = encodedImage(width: 1000, height: 1000, type: .png, opaque: false)
        let thumbnail = try #require(MediaProbe.imageThumbnail(data: data, maxPixelSize: 100, jpegQuality: 0.8))
        #expect(thumbnail.mimeType == "image/png")
        #expect(thumbnail.width == 100)
    }

    @Test func tiffConvertsToPng() throws {
        let tiff = encodedImage(width: 50, height: 40, type: .tiff)
        let png = try #require(MediaProbe.pngData(fromImageData: tiff))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        #expect(MediaProbe.probeImage(data: png) == ImageProbe(width: 50, height: 40, frameCount: 1))
    }
}

struct MediaProbeVideoTests {
    /// Writes a 1 second, 10 frame H.264 movie of 64 x 48 pixels.
    private func writeMovie(transform: CGAffineTransform = .identity) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 64,
            AVVideoHeightKey: 48,
        ])
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 48,
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< 10 {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 64, 48, kCVPixelFormatType_32ARGB, nil, &buffer)
            #expect(adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 10, timescale: 10))
        await writer.finishWriting()
        #expect(writer.status == .completed)
        return url
    }

    @Test func probeReadsDurationSizeAndPoster() async throws {
        let url = try await writeMovie()
        defer { try? FileManager.default.removeItem(at: url) }

        let probe = try #require(await MediaProbe.probeVideo(at: url, maxPixelSize: 800, jpegQuality: 0.8))
        #expect(abs(probe.duration - 1.0) < 0.2)
        #expect(probe.width == 64)
        #expect(probe.height == 48)
        let poster = try #require(probe.poster)
        #expect(poster.mimeType == "image/jpeg")
        #expect(poster.width == 64)
        #expect(poster.height == 48)
    }

    @Test func probeAppliesTheTrackTransform() async throws {
        let url = try await writeMovie(transform: CGAffineTransform(rotationAngle: .pi / 2))
        defer { try? FileManager.default.removeItem(at: url) }

        let probe = try #require(await MediaProbe.probeVideo(at: url, maxPixelSize: 800, jpegQuality: 0.8))
        #expect(probe.width == 48)
        #expect(probe.height == 64)
        #expect(probe.poster?.width == 48)
    }

    @Test func audioProbeReadsTheDurationOfATimedFile() async throws {
        let url = try await writeMovie()
        defer { try? FileManager.default.removeItem(at: url) }

        let duration = try #require(await MediaProbe.probeAudioDuration(at: url))
        #expect(abs(duration - 1.0) < 0.2)
    }

    @Test func probeRejectsANonMediaFile() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).mov")
        try Data("not a movie".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(await MediaProbe.probeVideo(at: url, maxPixelSize: 800, jpegQuality: 0.8) == nil)
    }
}
