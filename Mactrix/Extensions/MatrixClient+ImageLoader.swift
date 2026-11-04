import Core
import Foundation
import MatrixRustSDK
import OSLog
import SwiftUI
import UI

/// The Mac image loader. It decodes through `Data.toOrientedImage`, which
/// returns an `NSImage`, so the conformance stays in the app. The decoded
/// image cache it fills lives in Core.
extension MatrixClient: @retroactive UI.ImageLoader {
    public func cachedImage(matrixUrl: String) -> Image? {
        guard let nsImage = Self.imageCache.object(forKey: NSString(string: matrixUrl)) else { return nil }
        return Image(nsImage: nsImage)
    }

    public func loadImage(matrixUrl: String, size: CGSize?) async throws -> Image? {
        let cacheKey = if let size {
            NSString(string: "\(matrixUrl)_\(Int(size.width))x\(Int(size.height))")
        } else {
            NSString(string: matrixUrl)
        }
        if let cached = Self.imageCache.object(forKey: cacheKey) {
            return Image(nsImage: cached)
        }

        let mediaSource = try MediaSource.fromUrl(url: matrixUrl)

        let imageData: Data
        if let size {
            let width = UInt64(size.width)
            let height = UInt64(size.height)
            imageData = try await client.getMediaThumbnail(mediaSource: mediaSource, width: width, height: height)
        } else {
            imageData = try await client.getMediaContent(mediaSource: mediaSource)
        }

        do {
            let nsImage = try imageData.toOrientedImage(contentType: imageData.computeMimeType())
            Self.setCachedImage(nsImage, forKey: cacheKey)
            return Image(nsImage: nsImage)
        } catch {
            Logger.matrixClient.error("failed convert matrix media data to Image: \(error) \(imageData)")
            throw error
        }
    }
}
