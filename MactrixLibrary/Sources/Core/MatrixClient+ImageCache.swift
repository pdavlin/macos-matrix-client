import Foundation
import Tokens

public extension MatrixClient {
    // In-memory cache of decoded image objects. Purpose is rendering performance —
    // keeping decoded bitmaps ready to display prevents flicker when scrolling back to
    // previously viewed images. This is distinct from the SDK-level media download cache
    // (see clearCaches / getMediaFile(useCache:)) which avoids re-fetching from the server.
    // Costs are tracked in decoded RGBA bytes (width × height × 4), not compressed sizes,
    // since a typical JPEG can be 20-50× larger once decoded.
    static let imageCache: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.totalCostLimit = 256 * 1024 * 1024 // 256MB decoded pixels
        return cache
    }()

    private static let imageCacheMaxObjectCost = 64 * 1024 * 1024 // 64MB per object (~8000x2000px RGBA)

    static func setCachedImage(_ image: PlatformImage, forKey key: NSString) {
        let cost = Int(image.size.width * image.size.height) * 4 // decoded RGBA bytes
        guard cost <= imageCacheMaxObjectCost else { return }
        imageCache.setObject(image, forKey: key, cost: cost)
    }
}
