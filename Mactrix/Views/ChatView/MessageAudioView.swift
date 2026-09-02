import MatrixRustSDK
import Models
import OSLog
import QuickLook
import SwiftUI
import UI
import UniformTypeIdentifiers

/// An audio message (bridged voice notes included) rendered as an attachment
/// row: click for Quick Look playback, save-to-Downloads in the context menu.
struct MessageAudioView: View {
    @Environment(AppState.self) private var appState
    let content: AudioMessageContent

    @State private var media = MediaFileController()
    @State private var quickLookUrl: URL?

    var contentType: UTType? {
        return content.info?.mimetype.flatMap { UTType(mimeType: $0) }
    }

    var subtitle: String? {
        var parts: [String] = []
        if let duration = content.info?.duration {
            parts.append(Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
        }
        if let size = content.info?.size {
            parts.append(size.formatted(.byteCount(style: .file)))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func presentQuickLook() async {
        guard let url = await media.localFile(
            client: appState.matrixClient?.client,
            source: content.source,
            filename: content.filename,
            mimeType: content.info?.mimetype
        ) else { return }
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
                    icon: Image(nsImage: NSWorkspace.shared.icon(for: contentType ?? .audio)),
                    title: content.filename,
                    subtitle: subtitle
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
    }
}
