import Core
import MatrixRustSDK
import SwiftUI
import UI

/// The quote of a replied-to event, in a timeline row and in the composer's
/// reply bar. The details resolve to the same value the row's height
/// fingerprint holds (MATRIX-230).
struct EmbeddedMessageView: View {
    let embeddedEvent: MatrixRustSDK.EmbeddedEventDetails
    let action: () -> Void

    var body: some View {
        UI.ReplyQuoteView(quote: embeddedEvent.replyQuote, action: action)
    }
}
