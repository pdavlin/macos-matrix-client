import Core
import OSLog
import SwiftUI
import Tokens
import UI
import UIKit

/// A media message body on iOS (MATRIX-86): an inline box for images and
/// videos, an attachment row for audio and files, and the caption. A tap
/// downloads the file and opens the full-screen viewer.
///
/// Its height is a function of the event alone (`MediaBoxGeometry`, one line
/// for an attachment, the caption), so the loaded preview never moves it.
struct TimelineMediaView: View {
    let media: TimelineMedia
    let context: TimelineRowContext

    @State private var isDownloading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                Task { await open() }
            } label: {
                if media.kind.isVisual {
                    MediaPreviewBox(media: media, loader: context.media, isDownloading: isDownloading)
                } else {
                    AttachmentRowView(
                        icon: Image(systemName: media.kind.systemImage),
                        title: media.filename,
                        subtitle: media.subtitle
                    )
                    .lineLimit(1)
                    .overlay(alignment: .trailing) {
                        if isDownloading {
                            ProgressView()
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(media.kind.isVisual ? "Open" : "Open file") \(media.filename)")

            if let caption = media.caption, !caption.isEmpty {
                Text(caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Errors show in an alert, not inline: a new line here would
            // change the row height behind the measurement's back.
        }
        .alert(
            "Could not open \(media.filename)",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { isPresented in
                    guard !isPresented else { return }
                    errorMessage = nil
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func open() async {
        guard !isDownloading, let loader = context.media else { return }
        isDownloading = true
        defer { isDownloading = false }
        do {
            let item = try await loader.download(media)
            context.openMedia(item)
        } catch {
            Logger.mediaIOS.error("failed to download media: \(error)")
            errorMessage = error.localizedDescription
        }
    }
}

/// The inline image or video box: a fixed-size frame from the event's
/// dimensions, filled by the decoded preview when it arrives.
private struct MediaPreviewBox: View {
    let media: TimelineMedia
    let loader: (any TimelineMediaLoading)?
    let isDownloading: Bool

    @State private var image: UIImage?

    init(media: TimelineMedia, loader: (any TimelineMediaLoading)?, isDownloading: Bool) {
        self.media = media
        self.loader = loader
        self.isDownloading = isDownloading
        // A recycled cell shows a decoded preview at once, without a flash.
        if let key = media.previewKey {
            _image = State(initialValue: MatrixClient.imageCache.object(forKey: Self.cacheKey(key)))
        }
    }

    private static func cacheKey(_ previewKey: String) -> NSString {
        NSString(string: "\(previewKey)#ios-preview")
    }

    var body: some View {
        MediaBoxLayout(mediaWidth: media.width, mediaHeight: media.height) {
            // The flexible rectangle takes the box size; the overlays are
            // sized to it, so a filling image is clipped to the box.
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else if media.previewKey != nil {
                        ProgressView()
                    } else {
                        Image(systemName: media.kind.systemImage)
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay {
                    if isDownloading {
                        ProgressView()
                    } else if media.kind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: BubbleToken.mediaCornerRadius))
                .contentShape(Rectangle())
        }
        .task(id: media.previewKey, priority: .utility) {
            await loadPreview()
        }
    }

    private func loadPreview() async {
        guard image == nil, let key = media.previewKey, let loader else { return }
        let cacheKey = Self.cacheKey(key)
        if let cached = MatrixClient.imageCache.object(forKey: cacheKey) {
            image = cached
            return
        }
        do {
            let data = try await loader.previewData(for: media)
            let decoded = try await MediaThumbnailDecoder.decode(data)
            MatrixClient.setCachedImage(decoded, forKey: cacheKey)
            image = decoded
        } catch is CancellationError {
            /* the cell went away */
        } catch {
            Logger.mediaIOS.error("failed to load media preview: \(error)")
        }
    }
}

/// Sizes its content to `MediaBoxGeometry` for the proposed width.
private struct MediaBoxLayout: Layout {
    let mediaWidth: UInt64?
    let mediaHeight: UInt64?

    /// The width used when the proposal has none, as in an ideal-size query.
    private static let unspecifiedWidth: CGFloat = 320

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? Self.unspecifiedWidth
        return MediaBoxGeometry.size(proposedWidth: width, mediaWidth: mediaWidth, mediaHeight: mediaHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
        }
    }
}
