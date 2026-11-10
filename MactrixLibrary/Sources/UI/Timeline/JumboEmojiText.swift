import SwiftUI
import Tokens

/// An emoji-only message body, drawn large (MATRIX-137).
///
/// The caller decides with `Models.JumboEmoji.jumboText(body:formattedBody:)`
/// and passes the text that call returns. This view only draws it, so the
/// rule stays testable without a view.
///
/// It replaces the body text and nothing else: the row's header, reply
/// preview, edited marker, and reaction strip stay as they are. The font is
/// the system font at `TypographyToken.jumboEmojiSize`, with its own line
/// height, so one line of emoji gets the natural spacing of a 40 pt line.
/// The height is static, and the offscreen measurement draws this same view,
/// so the measured row height is the drawn one.
public struct JumboEmojiText: View {
    let text: String

    /// - Parameter text: the trimmed emoji-only body to draw.
    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        // Verbatim: the text is message content, never a localization key.
        Text(verbatim: text)
            .font(.system(size: TypographyToken.jumboEmojiSize))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        JumboEmojiText("👍")
        JumboEmojiText("🎉🎉🎉")
        JumboEmojiText("👨‍👩‍👧")
    }
    .frame(width: 400, alignment: .leading)
    .padding()
    .background(Color(PlatformColor.controlBackgroundColor))
}
