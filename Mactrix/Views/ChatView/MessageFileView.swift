import Core
import MatrixRustSDK
import Models
import OSLog
import QuickLook
import SwiftUI
import UI
import UniformTypeIdentifiers

struct MessageFileView: View {
    @Environment(AppState.self) private var appState
    let content: FileMessageContent

    @State private var icon: Image?
    @State private var media = MediaFileController()
    @State private var quickLookUrl: URL?

    var contentType: UTType? {
        return content.info?.mimetype.flatMap { UTType(mimeType: $0) }
    }

    var sizeText: String? {
        content.info?.size.map { $0.formatted(.byteCount(style: .file)) }
    }

    func presentQuickLook() async {
        guard let url = await media.localFile(
            client: appState.matrixClient?.client,
            source: content.source,
            filename: content.filename,
            mimeType: content.info?.mimetype
        ) else { return }

        // The downloaded file yields a richer icon (previews, correct type
        // even when the event carried no usable mimetype).
        icon = Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
        quickLookUrl = url
    }

    func saveToDownloads() async {
        await media.saveToDownloads(
            client: appState.matrixClient?.client,
            source: content.source,
            filename: content.filename,
            mimeType: content.info?.mimetype
        )
    }

    var body: some View {
        VStack {
            Button {
                Task { await presentQuickLook() }
            } label: {
                AttachmentRowView(
                    icon: icon ?? Image(nsImage: NSWorkspace.shared.icon(for: contentType ?? .data)),
                    title: content.filename,
                    subtitle: sizeText
                )
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Quick Look") {
                    Task { await presentQuickLook() }
                }
                Button("Save to Downloads") {
                    Task { await saveToDownloads() }
                }
            }

            if let caption = content.caption {
                Text(caption.formatAsMarkdown)
                    .textSelection(.enabled)
            }

            if let mediaError = media.errorMessage {
                MediaErrorLabel(message: mediaError)
            }
        }
        .quickLookPreview($quickLookUrl)
        .onChange(of: content.info?.mimetype, initial: true) { _, _ in
            let nsImage = NSWorkspace.shared.icon(for: contentType ?? .item)
            icon = Image(nsImage: nsImage)
        }
    }
}
