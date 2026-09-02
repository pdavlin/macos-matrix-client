import MatrixRustSDK
import Models
import OSLog
import QuickLook
import SwiftUI
import Tokens
import UI
import UniformTypeIdentifiers

struct MessageImageView: View {
    let content: ImageMessageContent

    @Environment(AppState.self) private var appState

    @State private var imageData: Data?
    @State private var image: Image?
    @State private var errorMessage: String?
    @State private var media = MediaFileController()
    @State private var quickLookUrl: URL?

    init(content: ImageMessageContent) {
        self.content = content
        if let cached = MatrixClient.imageCache.object(forKey: NSString(string: content.source.url())) {
            self._image = State(initialValue: Image(nsImage: cached))
        }
    }

    var aspectRatio: CGFloat? {
        MediaRowLayout.aspectRatio(width: content.info?.width, height: content.info?.height)
    }

    var maxHeight: CGFloat {
        MediaRowLayout.maxHeight(height: content.info?.height)
    }

    var contentType: UTType? {
        return content.info?.mimetype.flatMap { UTType(mimeType: $0) }
    }

    @ViewBuilder
    func imageView(image: Image) -> some View {
        Button(
            action: {
                Task { await presentQuickLook() }
            },
            label: {
                image
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: BubbleToken.mediaCornerRadius))
                    .onDrag {
                        let itemProvider = NSItemProvider()
                        itemProvider.suggestedName = content.filename
                        let data = imageData
                        itemProvider.registerDataRepresentation(for: UTType.image, visibility: .all) { completion in
                            completion(data, nil)
                            return nil
                        }
                        return itemProvider
                    }
            }
        )
        .buttonStyle(.plain)
        .contextMenu {
            Button("Quick Look") {
                Task { await presentQuickLook() }
            }
            Button("Save to Downloads") {
                Task { await saveToDownloads() }
            }
        }
    }

    var body: some View {
        VStack {
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .textSelection(.enabled)
                    .foregroundStyle(Color.red)
            } else {
                if let image {
                    imageView(image: image)
                } else {
                    ProgressView {
                        Text("Fetching image")
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
        }
        .quickLookPreview($quickLookUrl)
        .frame(maxHeight: maxHeight)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .task(id: content.source.url(), priority: .utility) {
            guard let matrixClient = appState.matrixClient else {
                errorMessage = "Matrix client not available"
                return
            }

            // Two caching layers serve different purposes:
            // - NSCache (checked in init): synchronously pre-populates `image` before the
            //   view appears, preventing flicker on scroll/revisit. Also skips the expensive
            //   decode step (toOrientedImage) on repeat loads below.
            // - SDK media cache (getMediaContent): avoids network re-fetches. Always called
            //   here so `imageData` is populated for drag-and-drop, even when the decoded
            //   NSImage is already in the NSCache.
            do {
                let data = try await matrixClient.client.getMediaContent(mediaSource: content.source)
                imageData = data

                let cacheKey = NSString(string: content.source.url())
                if let cached = MatrixClient.imageCache.object(forKey: cacheKey) {
                    image = Image(nsImage: cached)
                    return
                }

                let nsImage = try data.toOrientedImage(contentType: contentType)
                MatrixClient.setCachedImage(nsImage, forKey: cacheKey)
                image = Image(nsImage: nsImage)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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
}
