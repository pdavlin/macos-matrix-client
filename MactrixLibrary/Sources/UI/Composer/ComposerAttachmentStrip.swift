import Foundation
import Models
import SwiftUI
import Tokens

/// The pending attachments above the composer text field (MATRIX-106): one
/// chip for each, with a preview or a type icon, the filename, the size, and
/// a remove button.
///
/// The view only draws the chips and reports a removal. The composer owns
/// the list: the remove button, or Esc or Delete on a focused chip, calls
/// `onRemove`.
public struct ComposerAttachmentStrip: View {
    let attachments: [ComposerAttachment]
    let onRemove: (ComposerAttachment.ID) -> Void

    /// - Parameters:
    ///   - attachments: the pending attachments, in send order.
    ///   - onRemove: called with the id of the attachment to remove.
    public init(attachments: [ComposerAttachment], onRemove: @escaping (ComposerAttachment.ID) -> Void) {
        self.attachments = attachments
        self.onRemove = onRemove
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ComposerAttachmentToken.chipSpacing) {
                ForEach(attachments) { attachment in
                    ComposerAttachmentChip(attachment: attachment) {
                        onRemove(attachment.id)
                    }
                }
            }
            .padding(.horizontal, ComposerAttachmentToken.chipPadding)
            .padding(.top, ComposerAttachmentToken.chipPadding)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Attachments"))
    }
}

/// One pending attachment chip.
struct ComposerAttachmentChip: View {
    let attachment: ComposerAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ComposerAttachmentPreview(attachment: attachment)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: ComposerAttachmentToken.filenameMaxWidth, alignment: .leading)
                if let sizeText {
                    Text(sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Remove \(attachment.filename)"))
        }
        .padding(ComposerAttachmentToken.chipPadding)
        .background(
            RoundedRectangle(cornerRadius: ComposerAttachmentToken.chipCornerRadius)
                .fill(Color.primary.opacity(ComposerAttachmentToken.chipBackgroundOpacity))
        )
        .focusable()
        .onKeyPress(keys: [.escape, .delete, .deleteForward]) { _ in
            onRemove()
            return .handled
        }
        .accessibilityElement(children: .combine)
    }

    /// The file size, for example "4.2 MB". Nil if it is unknown.
    private var sizeText: String? {
        attachment.byteCount.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .file) }
    }
}

/// The preview image of a chip, or an icon for the attachment kind while the
/// preview is not ready or when there is none.
struct ComposerAttachmentPreview: View {
    let attachment: ComposerAttachment

    var body: some View {
        Group {
            if let image = previewImage {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: Self.iconName(for: attachment.kind))
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: ComposerAttachmentToken.previewSize, height: ComposerAttachmentToken.previewSize)
        .clipShape(RoundedRectangle(cornerRadius: ComposerAttachmentToken.previewCornerRadius))
        .overlay {
            if attachment.kind == .video, previewImage != nil {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.white)
                    .shadow(radius: 1)
            }
        }
        .accessibilityHidden(true)
    }

    private var previewImage: Image? {
        guard let data = attachment.measurement?.preview?.data, let platformImage = PlatformImage(data: data) else {
            return nil
        }
        #if canImport(AppKit)
            return Image(nsImage: platformImage)
        #else
            return Image(uiImage: platformImage)
        #endif
    }

    /// The SF Symbol for an attachment kind.
    static func iconName(for kind: MediaSendKind) -> String {
        switch kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .file: "doc"
        }
    }
}

#Preview {
    ComposerAttachmentStrip(
        attachments: [
            ComposerAttachment(
                source: .file(URL(fileURLWithPath: "/tmp/quarterly-report.pdf")),
                filename: "quarterly-report.pdf",
                kind: .file,
                mimeType: "application/pdf",
                byteCount: 1_200_000,
                measurement: .empty
            ),
            ComposerAttachment(
                source: .file(URL(fileURLWithPath: "/tmp/holiday.mov")),
                filename: "holiday.mov",
                kind: .video,
                mimeType: "video/quicktime",
                byteCount: 48_000_000
            ),
        ],
        onRemove: { _ in }
    )
    .frame(width: 420)
}
