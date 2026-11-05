import Models
import SwiftUI

/// The confirmation before a message is forwarded (MATRIX-112, M2-B5, D-4).
///
/// It names the target room, shows a preview, and for media the file size:
/// "Forward 24.3 MB video to Alice?". Cancel is the default button, so Return
/// never forwards by accident. Escape also cancels. While the forward goes to
/// the send queue (a media forward downloads the file first), a spinner
/// shows and both buttons are disabled. The sheet makes no SDK call.
///
/// Usage:
/// ```swift
/// .sheet(item: confirmingBinding) { step in
///     MessageForwardSheet(content: step.request.content, roomName: step.target?.name,
///                         isSending: flow.isSending, onForward: { ... }, onCancel: { ... })
/// }
/// ```
public struct MessageForwardSheet: View {
    let content: MessageForwardContent
    let roomName: String?
    let isSending: Bool
    let onForward: () -> Void
    let onCancel: () -> Void

    /// Set by snapshot tests to swap the indeterminate spinner for a static
    /// substitute. Production never sets it.
    @Environment(\.usesStaticProgressIndicators) private var usesStaticProgressIndicators
    @Environment(\.locale) private var locale

    /// - Parameters:
    ///   - content: What the forward sends again.
    ///   - roomName: The target room's display name, or nil when it has none.
    ///   - isSending: Whether the confirmed forward is on its way to the send
    ///     queue.
    ///   - onForward: Runs when the person confirms.
    ///   - onCancel: Runs when the person cancels.
    public init(
        content: MessageForwardContent,
        roomName: String?,
        isSending: Bool,
        onForward: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.content = content
        self.roomName = roomName
        self.isSending = isSending
        self.onForward = onForward
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "arrowshape.turn.up.right")
                .font(.title2)
                .bold()
                .fixedSize(horizontal: false, vertical: true)

            preview

            HStack {
                if isSending {
                    spinner
                    Text("Forwarding…")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Forward", action: onForward)
                    .disabled(isSending)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSending)
            }
        }
        .padding(20)
        .sheetContentWidth(440)
        .cancelsOnExitCommand { if !isSending { onCancel() } }
        .interactiveDismissDisabled(isSending)
    }

    // MARK: - Parts

    /// The quoted message: the file row for media, then the text.
    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case let .media(media) = content {
                AttachmentRowView(
                    icon: Image(systemName: Self.systemImage(of: media.kind)),
                    title: media.filename,
                    subtitle: sizeText
                )
            }
            if let text = MessageForwardPreview.text(of: content) {
                Text(text)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder private var spinner: some View {
        if usesStaticProgressIndicators {
            // Snapshot-only: a ring drawn with SwiftUI shapes, at the small
            // spinner's 16 pt (see `RecoveryKeyEntrySheet`).
            Circle()
                .trim(from: 0, to: 0.5)
                .stroke(.secondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 16, height: 16)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Wording

    /// The question the sheet asks. One full sentence per case, so each
    /// translation can order the words as its language needs.
    var title: LocalizedStringKey {
        let room = roomName ?? String(localized: "the chosen room")
        switch content {
        case .text:
            return "Forward this message to \(room)?"
        case let .media(media):
            guard let size = sizeText else {
                switch media.kind {
                case .image: return "Forward this image to \(room)?"
                case .video: return "Forward this video to \(room)?"
                case .audio: return "Forward this audio file to \(room)?"
                case .file: return "Forward this file to \(room)?"
                }
            }
            switch media.kind {
            case .image: return "Forward \(size) image to \(room)?"
            case .video: return "Forward \(size) video to \(room)?"
            case .audio: return "Forward \(size) audio file to \(room)?"
            case .file: return "Forward \(size) file to \(room)?"
            }
        }
    }

    /// The media size in the view's locale, or nil.
    private var sizeText: String? {
        MessageForwardPreview.sizeText(of: content, locale: locale)
    }

    /// The icon of the file row, as the timeline rows draw each kind.
    static func systemImage(of kind: MediaSendKind) -> String {
        switch kind {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .file: "doc"
        }
    }
}
