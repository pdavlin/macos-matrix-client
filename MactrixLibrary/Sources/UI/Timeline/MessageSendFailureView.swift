import SwiftUI
import Tokens

/// Failure surface for a local echo whose send failed.
///
/// Rendered under the message body of the failed event. The SDK's send queue
/// owns the failure and the retry; this view only shows the cause it reported
/// and hands the user's choice back through the closures.
public struct MessageSendFailureView: View {
    let message: String
    let retry: () -> Void
    let discard: () -> Void

    @Environment(\.timelineTypography) private var typography

    public init(message: String, retry: @escaping () -> Void, discard: @escaping () -> Void) {
        self.message = message
        self.retry = retry
        self.discard = discard
    }

    public var body: some View {
        HStack(spacing: DensityToken.sendFailureSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text("Not sent — \(message)")
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .buttonStyle(.link)
            Button("Discard", action: discard)
                .buttonStyle(.link)
        }
        .font(.system(size: typography.footnote))
        .padding(.top, DensityToken.sendFailureTopPadding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Message not sent: \(message)")
    }
}

#Preview {
    VStack(alignment: .leading) {
        MessageSendFailureView(
            message: "the server rejected the message",
            retry: {},
            discard: {}
        )
        MessageSendFailureView(
            message: "a previously verified user's identity changed",
            retry: {},
            discard: {}
        )
    }
    .padding()
}
