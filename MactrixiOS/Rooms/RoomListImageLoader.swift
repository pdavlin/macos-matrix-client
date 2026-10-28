import Core
import MatrixRustSDK
import OSLog
import SwiftUI
import UI
import UIKit

/// The iOS avatar loader for the room list. It mirrors the Mac
/// `MatrixClient: UI.ImageLoader` conformance, but decodes with `UIImage`,
/// which applies EXIF orientation itself. It is a wrapper, not a retroactive
/// conformance on `MatrixClient`, so it cannot collide with a conformance
/// that another iOS story adds.
struct RoomListImageLoader: UI.ImageLoader {
    struct UndecodableImageError: LocalizedError {
        var errorDescription: String? {
            "The media data is not an image."
        }
    }

    let matrixClient: MatrixClient

    func cachedImage(matrixUrl: String) -> Image? {
        MatrixClient.imageCache.object(forKey: NSString(string: matrixUrl)).map(Image.init(uiImage:))
    }

    func loadImage(matrixUrl: String, size: CGSize?) async throws -> Image? {
        let cacheKey = if let size {
            NSString(string: "\(matrixUrl)_\(Int(size.width))x\(Int(size.height))")
        } else {
            NSString(string: matrixUrl)
        }
        if let cached = MatrixClient.imageCache.object(forKey: cacheKey) {
            return Image(uiImage: cached)
        }

        // `reset()` nils the client on sign out while avatar tasks can still run.
        guard let client = matrixClient.client else { return nil }

        let mediaSource = try MediaSource.fromUrl(url: matrixUrl)

        let imageData: Data = if let size {
            try await client.getMediaThumbnail(
                mediaSource: mediaSource,
                width: UInt64(size.width),
                height: UInt64(size.height)
            )
        } else {
            try await client.getMediaContent(mediaSource: mediaSource)
        }

        guard let image = UIImage(data: imageData) else {
            Logger.roomList.error("failed to decode avatar data (\(imageData.count, privacy: .public) bytes)")
            throw UndecodableImageError()
        }
        MatrixClient.setCachedImage(image, forKey: cacheKey)
        return Image(uiImage: image)
    }
}
