import AVKit
import MatrixRustSDK
import Models
import OSLog
import QuickLook
import SwiftUI
import Tokens
import UI

struct MessageVideoView: View {
    @Environment(AppState.self) private var appState
    let content: VideoMessageContent

    @State private var media = MediaFileController()
    @State private var quickLookUrl: URL?
    @State private var video: AVPlayer?

    var aspectRatio: CGFloat? {
        MediaRowLayout.aspectRatio(width: content.info?.width, height: content.info?.height)
    }

    var maxHeight: CGFloat {
        MediaRowLayout.maxHeight(height: content.info?.height)
    }

    func presentQuickLook() async {
        guard let url = await localFile() else { return }
        quickLookUrl = url
    }

    func playInline() async {
        guard let url = await localFile() else { return }
        let player = AVPlayer(url: url)
        video = player
        player.play()
    }

    func localFile() async -> URL? {
        await media.localFile(
            client: appState.matrixClient?.client,
            source: content.source,
            filename: content.filename,
            mimeType: content.info?.mimetype
        )
    }

    func saveToDownloads() async {
        await media.saveToDownloads(
            client: appState.matrixClient?.client,
            source: content.source,
            filename: content.filename,
            mimeType: content.info?.mimetype
        )
    }

    @ViewBuilder
    var saveButton: some View {
        Button("Save to Downloads") {
            Task { await saveToDownloads() }
        }
    }

    var body: some View {
        VStack {
            if let video {
                TimelineVideoPlayer(videoPlayer: video)
                    .cornerRadius(BubbleToken.mediaCornerRadius)
                    .contextMenu {
                        Button("Quick Look") {
                            Task { await presentQuickLook() }
                        }
                        saveButton
                    }
            } else {
                Button {
                    Task { await presentQuickLook() }
                } label: {
                    MatrixImageView(mediaSource: content.info?.thumbnailSource, mimeType: content.info?.thumbnailInfo?.mimetype)
                        .overlay {
                            if media.isDownloading {
                                ProgressView()
                            } else {
                                Image(systemName: "play.fill")
                                    .resizable()
                                    .foregroundStyle(.white)
                                    .shadow(radius: 4)
                                    .frame(width: 48, height: 48)
                                    .opacity(0.9)
                            }
                        }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Play Inline") {
                        Task { await playInline() }
                    }
                    saveButton
                }
            }
            if let caption = content.caption, !caption.isEmpty {
                Text(caption.formatAsMarkdown)
                    .textSelection(.enabled)
            }
            if let mediaError = media.errorMessage {
                MediaErrorLabel(message: mediaError)
            }
        }
        .quickLookPreview($quickLookUrl)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: maxHeight)
        .frame(minHeight: content.info?.thumbnailSource == nil ? maxHeight : nil)
    }
}
