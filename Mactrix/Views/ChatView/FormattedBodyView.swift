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

    init(messageContent: some Core.MessageContent) {
        self.rawBody = messageContent.body

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
            AttributedTextView(attributedString: parseFormattedBody(htmlBody, baseFontSize: typography.base))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(rawBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
