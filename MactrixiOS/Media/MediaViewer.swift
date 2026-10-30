import OSLog
import Photos
import QuickLook
import SwiftUI
import UIKit

/// A downloaded media file the viewer shows (MATRIX-86).
struct MediaViewerItem: Identifiable {
    let id = UUID()
    let url: URL
    let kind: TimelineMedia.Kind
    let title: String
    /// Keeps the SDK's temp file alive while the viewer shows it. Nil when
    /// the file is not owned by a handle (the DEBUG fixture).
    let fileHandle: AnyObject?
}

/// The full-screen media viewer (MATRIX-86): Quick Look for the file, with
/// Save to Photos for images and videos, and the share sheet, which carries
/// Save to Files.
struct MediaViewerScreen: View {
    let item: MediaViewerItem

    @Environment(\.dismiss) private var dismiss
    @State private var saveStatus: SaveStatus = .idle

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)

        var failureMessage: String? {
            guard case let .failed(message) = self else { return nil }
            return message
        }
    }

    var body: some View {
        NavigationStack {
            QuickLookPreview(url: item.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(item.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        if item.kind.canSaveToPhotos {
                            Button {
                                Task { await saveToPhotos() }
                            } label: {
                                Label("Save to Photos", systemImage: saveStatus == .saved ? "checkmark" : "square.and.arrow.down")
                            }
                            .disabled(saveStatus == .saving || saveStatus == .saved)
                        }
                        ShareLink(item: item.url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .alert(
                    "Could not save to Photos",
                    isPresented: Binding(
                        get: { saveStatus.failureMessage != nil },
                        set: { isPresented in
                            guard !isPresented else { return }
                            saveStatus = .idle
                        }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(saveStatus.failureMessage ?? "")
                }
        }
    }

    private func saveToPhotos() async {
        saveStatus = .saving
        do {
            try await PhotoLibrarySaver.save(fileAt: item.url, kind: item.kind)
            saveStatus = .saved
        } catch {
            Logger.mediaIOS.error("failed to save media to Photos: \(error)")
            saveStatus = .failed(error.localizedDescription)
        }
    }
}

/// Adds a media file to the photo library with add-only access.
enum PhotoLibrarySaver {
    struct NotAuthorizedError: LocalizedError {
        var errorDescription: String? {
            "Mactrix has no permission to add to your photo library. Allow it in Settings."
        }
    }

    static func save(fileAt url: URL, kind: TimelineMedia.Kind) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw NotAuthorizedError() }
        let isVideo = kind == .video
        try await PHPhotoLibrary.shared().performChanges {
            if isVideo {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } else {
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
            }
        }
    }
}

/// `QLPreviewController` for one local file.
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        guard context.coordinator.url != url else { return }
        context.coordinator.url = url
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in _: QLPreviewController) -> Int {
            1
        }

        func previewController(_: QLPreviewController, previewItemAt _: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
