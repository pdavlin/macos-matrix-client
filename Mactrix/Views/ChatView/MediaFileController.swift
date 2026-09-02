import AppKit
import MatrixRustSDK
import OSLog
import SwiftUI
import Utils

/// Downloads a timeline media item to a local file through the SDK and backs
/// the two actions every media row shares: Quick Look and save-to-Downloads.
///
/// The SDK's `MediaFileHandle` owns the temp file on disk — the file is
/// deleted when the handle drops — so the controller keeps the handle alive
/// for as long as the owning row's state lives.
@MainActor
@Observable
final class MediaFileController {
    private(set) var isDownloading = false
    private(set) var errorMessage: String?

    private var fileHandle: MediaFileHandle?
    private var localUrl: URL?

    /// The local file for the media, downloading it through the SDK on the
    /// first call. Returns nil (and sets `errorMessage`) on failure.
    func localFile(
        client: ClientProtocol?,
        source: MediaSource,
        filename: String,
        mimeType: String?
    ) async -> URL? {
        if let localUrl {
            return localUrl
        }
        guard let client else {
            errorMessage = "Matrix client not available"
            return nil
        }
        guard !isDownloading else { return nil }

        isDownloading = true
        defer { isDownloading = false }
        errorMessage = nil

        do {
            let handle = try await client.getMediaFile(
                mediaSource: source,
                filename: filename,
                mimeType: mimeType ?? "",
                useCache: true,
                tempDir: NSTemporaryDirectory()
            )
            fileHandle = handle
            let url = try URL(filePath: handle.path(), directoryHint: .notDirectory)
            localUrl = url
            Logger.viewCycle.debug("downloaded media file \(url.absoluteString)")
            return url
        } catch {
            Logger.viewCycle.error("failed to download media file: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Copies the media into the user's Downloads folder under a
    /// collision-free name and reveals it in Finder. Downloads first when the
    /// local file is not there yet.
    func saveToDownloads(
        client: ClientProtocol?,
        source: MediaSource,
        filename: String,
        mimeType: String?
    ) async {
        guard let localUrl = await localFile(
            client: client, source: source, filename: filename, mimeType: mimeType
        ) else { return }

        guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
            errorMessage = "Downloads folder not available"
            return
        }

        let destination = MediaDownloads.uniqueDestination(directory: downloads, filename: filename) { url in
            FileManager.default.fileExists(atPath: url.path)
        }

        do {
            try await Task.detached(priority: .utility) {
                try FileManager.default.copyItem(at: localUrl, to: destination)
            }.value
            Logger.viewCycle.debug("saved media to \(destination.absoluteString)")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            Logger.viewCycle.error("failed to save media to Downloads: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}
