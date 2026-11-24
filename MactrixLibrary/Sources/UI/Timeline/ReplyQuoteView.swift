import Models
import SwiftUI

/// The quote a reply draws above its body: a placeholder while the replied-to
/// event loads, then the sender and the text (MATRIX-230).
///
/// It draws from the value the row's height fingerprint holds, so a row is
/// measured again exactly when its quote changes what it lays out.
public struct ReplyQuoteView: View {
    let quote: ReplyQuoteGeometry
    let action: () -> Void

    /// The placeholder's text. It only gives the redacted placeholder its
    /// shape: a name line and a message line.
    static let placeholderUsername = "loading@username.org"
    static let placeholderMessage = "Phasellus sit amet purus ac enim semper convallis. Nullam a gravida libero."

    public init(quote: ReplyQuoteGeometry, action: @escaping () -> Void = {}) {
        self.quote = quote
        self.action = action
    }

    public var body: some View {
        switch quote {
        case .placeholder:
            MessageReplyView(username: Self.placeholderUsername, message: Self.placeholderMessage, action: action)
                .redacted(reason: .placeholder)
        case let .quote(sender, text):
            MessageReplyView(username: sender, message: text, action: action)
        case let .failed(message):
            Text("error: \(message)")
        }
    }
}
