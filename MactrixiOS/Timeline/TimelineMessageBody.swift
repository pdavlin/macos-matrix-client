import Core
import MatrixRustSDK
import Models
import SwiftUI
import UI

/// The body of an SDK message on iOS: formatted text, media, or a one-line
/// label for kinds outside the M1 read path.
struct TimelineMessageBody: View {
    let kind: MatrixRustSDK.MsgLikeKind
    let context: TimelineRowContext

    var body: some View {
        switch kind {
        case let .message(content: content):
            VStack(alignment: .leading, spacing: 2) {
                messageType(content.msgType)
                if content.isEdited {
                    UI.EditedMarker()
                }
            }
        case let .sticker(body, _, _):
            label("Sticker", body)
        case let .poll(question, _, _, _, _, _, _):
            label("Poll", question)
        case .redacted:
            Text("Message redacted")
                .italic()
                .foregroundStyle(.secondary)
        case let .unableToDecrypt(msg: encrypted):
            UI.UnableToDecryptView(cause: Models.UnableToDecryptCause(encrypted: encrypted))
        case let .other(eventType):
            label("Custom event", eventType.description)
        case let .liveLocation(content):
            label("Live location", content.description ?? "no description")
        }
    }

    @ViewBuilder
    private func messageType(_ type: MatrixRustSDK.MessageType) -> some View {
        switch type {
        case let .text(content):
            TimelineFormattedText(
                text: content.body,
                html: content.formatted?.format == .html ? content.formatted?.body : nil,
                imageLoader: context.imageLoader
            )
        case let .notice(content):
            wrapped(content.body)
                .foregroundStyle(.secondary)
        case let .emote(content):
            wrapped("* \(content.body)")
        case .image, .video, .audio, .file:
            if let media = TimelineMedia(type) {
                TimelineMediaView(media: media, context: context)
            }
        case let .gallery(content):
            label("Gallery", content.body)
        case let .location(content):
            label("Location", content.body)
        case let .other(msgtype, body):
            label(msgtype, body)
        }
    }

    private func wrapped(_ text: String) -> some View {
        Text(text.formatAsMarkdown)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ title: String, _ detail: String) -> some View {
        Text("\(title): \(detail)")
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
