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
    /// The emoji-only body to draw large, or nil for ordinary text
    /// (MATRIX-137). Decided once here from the same two bodies the height
    /// fingerprint compares, so a flip always re-measures the row.
    let jumboText: String?
    /// Loads the custom emoticons of an HTML body (MATRIX-153).
    let imageLoader: (any UI.ImageLoader)?

    init(messageContent: some Core.MessageContent, imageLoader: (any UI.ImageLoader)?) {
        self.rawBody = messageContent.body
        self.imageLoader = imageLoader

        if let formatted = messageContent.formatted, formatted.format == .html {
            self.htmlBody = formatted.body
        } else {
            self.htmlBody = nil
        }

        self.jumboText = Models.JumboEmoji.jumboText(body: rawBody, formattedBody: htmlBody)
    }

    var body: some View {
        if let jumboText {
            UI.JumboEmojiText(jumboText)
        } else if let htmlBody {
            FormattedBodyText(html: htmlBody, baseFontSize: typography.base, imageLoader: imageLoader)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(rawBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
