import SwiftUI

/// The bar under the iOS timeline (MATRIX-86): the reply preview, when there
/// is a reply target, above the text field and the send button.
///
/// It sits on the standard bar material: it is navigation chrome, not
/// timeline content, so the glass rule allows it.
struct ComposerBar: View {
    let target: ComposerTarget
    let placeholder: String

    @State private var model = ComposerModel()

    var body: some View {
        VStack(spacing: 0) {
            if let reply = target.reply {
                ComposerReplyPreview(reply: reply) {
                    target.cancelReply()
                }
                Divider()
            }
            HStack(alignment: .bottom, spacing: 8) {
                ComposerTextView(text: $model.text, placeholder: placeholder)
                    .overlay(alignment: .topLeading) {
                        if model.text.isEmpty {
                            Text(placeholder)
                                .foregroundStyle(.tertiary)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                Button {
                    Task { await model.send(to: target) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .symbolRenderingMode(.hierarchical)
                }
                .disabled(!model.canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("composerSend")
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
        .task(id: model.text) {
            // As the Mac composer: a notice on every non-empty change. The
            // SDK times it out, and sending clears it.
            guard !model.text.isEmpty else { return }
            await target.noteTyping()
        }
    }
}

/// The reply target above the composer field, with a cancel button.
struct ComposerReplyPreview: View {
    let reply: ComposerReply
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrowshape.turn.up.left")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Replying to \(reply.senderName)")
                    .font(.footnote.bold())
                Text(reply.preview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: cancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Cancel reply")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityIdentifier("composerReplyPreview")
    }
}
