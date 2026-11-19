import AppKit
import MatrixRustSDK
import OSLog
import SwiftUI
import UI
import Utils

/// Downloads a timeline media item to a local file through the SDK and backs
/// the two actions every media row shares: Quick Look and save-to-Downloads.
///
/// The SDK's `MediaFileHandle` owns the temp file on disk — the file is
/// deleted when the handle drops — so the controller keeps the handle alive
/// for as long as the owning row's state lives. Quick Look holds the handle
/// too while its panel shows the file (MATRIX-199).
@MainActor
@Observable
final class MediaFileController {
    private(set) var isDownloading = false
    private(set) var errorMessage: String?

    private var fileHandle: MediaFileHandle?
    private var localUrl: URL?
    /// The media the local file is for. The table reuses a row's view, and
    /// with it this controller, for another message of the same kind.
    private var localSourceUrl: String?

    /// The local file for the media, downloading it through the SDK on the
    /// first call. Returns nil (and sets `errorMessage`) on failure.
    func localFile(
        client: ClientProtocol?,
        source: MediaSource,
        filename: String,
        mimeType: String?
    ) async -> URL? {
        if let localUrl, localSourceUrl == source.url() {
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
            let url = try URL(filePath: handle.path(), directoryHint: .notDirectory)
            fileHandle = handle
            localUrl = url
            localSourceUrl = source.url()
            Logger.viewCycle.debug("downloaded media file \(url.absoluteString)")
            return url
        } catch {
            Logger.viewCycle.error("failed to download media file: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Shows the media in the Quick Look panel, downloading it first when
    /// the local file is not there yet. Returns the local file, or nil on
    /// failure.
    ///
    /// The app-wide presenter, not the row, owns the preview (MATRIX-199): it
    /// takes the panel from the composer and holds the file handle, so the
    /// preview outlives a row the table rebuilds.
    @discardableResult
    func quickLook(
        client: ClientProtocol?,
        source: MediaSource,
        filename: String,
        mimeType: String?
    ) async -> URL? {
        // The window of the click. The download can take long enough for
        // the user to move to another window.
        let window = NSApp.keyWindow
        guard let url = await localFile(
            client: client, source: source, filename: filename, mimeType: mimeType
        ), let fileHandle else { return nil }
        QuickLookPresenter.shared.present(url: url, keepAlive: fileHandle, in: window)
        return url
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
