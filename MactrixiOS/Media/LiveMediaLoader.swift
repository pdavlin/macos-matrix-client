import Foundation
import MatrixRustSDK
import OSLog

/// Fetches media for a live room (MATRIX-86) with the calls the Mac media
/// rows make: `getMediaContent` for previews, `getMediaFile` for the viewer.
@MainActor
struct LiveMediaLoader: TimelineMediaLoading {
    struct NoSourceError: LocalizedError {
        var errorDescription: String? {
            "The message has no media to fetch."
        }
    }

    let client: ClientProtocol

    func previewData(for media: TimelineMedia) async throws -> Data {
        guard let source = media.previewSource else { throw NoSourceError() }
        return try await client.getMediaContent(mediaSource: source)
    }

    /// Downloads through the SDK's media cache into a temp file. The SDK's
    /// `MediaFileHandle` deletes the file when it drops, so the viewer item
    /// keeps the handle for as long as the viewer shows the file.
    func download(_ media: TimelineMedia) async throws -> MediaViewerItem {
        guard let source = media.source else { throw NoSourceError() }
        let handle = try await client.getMediaFile(
            mediaSource: source,
            filename: media.filename,
            mimeType: media.mimeType ?? "",
            useCache: true,
            tempDir: NSTemporaryDirectory()
        )
        let url = try URL(filePath: handle.path(), directoryHint: .notDirectory)
        Logger.mediaIOS.debug("downloaded media file \(url.lastPathComponent, privacy: .public)")
        return MediaViewerItem(url: url, kind: media.kind, title: media.filename, fileHandle: handle)
    }
}

extension Logger {
    static let mediaIOS = Logger(subsystem: "io.davlin.matrixclient.ios", category: "media")
}
