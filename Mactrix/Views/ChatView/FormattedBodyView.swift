import MatrixRustSDK
import MessageFormatting
import SwiftUI
import Tokens

struct FormattedBodyView: View {
    @Environment(\.timelineTypography) private var typography

    let rawBody: String
    let htmlBody: String?

    init(messageContent: some MessageContent) {
        self.rawBody = messageContent.body

        if let formatted = messageContent.formatted, formatted.format == .html {
            self.htmlBody = formatted.body
        } else {
            self.htmlBody = nil
        }
    }

    var body: some View {
        if let htmlBody {
            AttributedTextView(attributedString: parseFormattedBody(htmlBody, baseFontSize: typography.base))
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(rawBody)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
