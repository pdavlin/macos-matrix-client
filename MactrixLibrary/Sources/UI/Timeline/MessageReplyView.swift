import SwiftUI
import Tokens

public struct MessageReplyView: View {
    let username: String
    let message: String
    let action: () -> Void

    public init(username: String, message: String, action: @escaping () -> Void = {}) {
        self.username = username
        self.message = message
        self.action = action
    }

    var content: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(username)
                    .bold()
                    .textSelection(.enabled)
                Text(message.formatAsMarkdown)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
        .padding(.vertical, DensityToken.rowVerticalPadding)
        .background(
            ZStack {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: BubbleToken.cornerRadius).opacity(BubbleToken.replyBarOpacity).frame(width: BubbleToken.replyBarWidth)
                    Spacer()
                }
                RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                    .padding(.leading, BubbleToken.replyBackgroundInset)
                    .opacity(BubbleToken.replyBackgroundOpacity)
            }
        )
        .italic()
    }

    public var body: some View {
        Button {
            action()
        } label: {
            content
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        MessageReplyView(username: "user@example.com", message: "This is the root message")
        Text("Real content")
    }.padding()
}
