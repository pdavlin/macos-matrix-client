import Core
import MatrixRustSDK
import MessageFormatting
import Models
import SwiftUI
import Tokens
import UI

struct FormattedBodyView: View {
    @Environment(\.timelineTypography) private var typography

    let rawBody: String
    let htmlBody: String?
    /// How an emoji-only body draws large, or nil for body size (MATRIX-137,
    /// MATRIX-162). The row's height fingerprint decides it once, at map
    /// time, from the two bodies it compares, so a flip always re-measures
    /// the row.
    let jumboEmoji: Models.JumboEmoji.Kind?
    /// Loads the custom emoticons of an HTML body (MATRIX-153).
    let imageLoader: (any UI.ImageLoader)?
    /// Takes the custom emoticons of an HTML body when it shows
    /// (MATRIX-161): the learned emoji of the chat's workspace.
    let onEmoticons: (@MainActor ([BodyEmoticon]) -> Void)?

    /// - Parameter bodyGeometry: The body of the row's height fingerprint,
    ///   when the caller has one. It holds the jumbo decision. Without it,
    ///   the view decides here from the same two bodies.
    init(
        messageContent: some Core.MessageContent,
        bodyGeometry: Models.MessageBodyGeometry? = nil,
        imageLoader: (any UI.ImageLoader)?,
        onEmoticons: (@MainActor ([BodyEmoticon]) -> Void)? = nil
    ) {
        self.rawBody = messageContent.body
        self.imageLoader = imageLoader
        self.onEmoticons = onEmoticons

        if let formatted = messageContent.formatted, formatted.format == .html {
            self.htmlBody = formatted.body
        } else {
            self.htmlBody = nil
        }

        if let bodyGeometry, bodyGeometry.variant == "text" {
            self.jumboEmoji = bodyGeometry.jumboEmoji
        } else {
            self.jumboEmoji = Models.JumboEmoji.kind(body: rawBody, formattedBody: htmlBody)
        }
    }

    var body: some View {
        if jumboEmoji == .text {
            UI.JumboEmojiText(rawBody.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let htmlBody {
            FormattedBodyText(
                html: htmlBody,
                baseFontSize: typography.base,
                isJumbo: jumboEmoji == .formatted,
                imageLoader: imageLoader,
                onEmoticons: onEmoticons
            )
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(rawBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
