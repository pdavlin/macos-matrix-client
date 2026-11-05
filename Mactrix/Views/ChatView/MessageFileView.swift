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
    /// The row's actions. The menu over the attachment shows them with the
    /// media actions this view performs (MATRIX-108).
    let rowActions: MessageActionTarget

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

    /// Performs the media actions here and hands the rest to the row.
    func performMenuAction(_ action: MessageAction) {
        switch action {
        case .quickLook:
            Task { await presentQuickLook() }
        case .saveToDownloads:
            Task { await saveToDownloads() }
        default:
            rowActions.perform(action)
        }
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
                UI.MessageActionMenu(
                    items: MessageActionModel.items(for: rowActions.subject, on: .contextMenu),
                    perform: performMenuAction
                )
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
