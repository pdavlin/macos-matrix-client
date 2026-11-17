import SwiftUI
import Tokens

/// The one-line notice above the main composer for a reply to a thread that
/// was not sent (MATRIX-173).
///
/// The main timeline hides threaded events, so without this line a failed
/// reply to a thread shows only in the thread panel. The SDK's send queue
/// owns the failure and the retry; this view shows the line and hands the
/// user's choice back through the closures.
///
/// The background is opaque: the notice is content, not navigation.
public struct ThreadReplyNoticeView: View {
    let retry: () -> Void
    let openThread: (() -> Void)?
    let discard: () -> Void

    /// - Parameters:
    ///   - retry: Called when Retry is clicked.
    ///   - openThread: Called when Open Thread is clicked, or nil where no
    ///     thread panel is available (a merged chat). The button is then
    ///     left out.
    ///   - discard: Called when Discard is clicked.
    public init(retry: @escaping () -> Void, openThread: (() -> Void)?, discard: @escaping () -> Void) {
        self.retry = retry
        self.openThread = openThread
        self.discard = discard
    }

    public var body: some View {
        HStack(spacing: DensityToken.sendFailureSpacing) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text("Reply to thread not sent")
                .foregroundStyle(.red)
                .lineLimit(1)
            Spacer(minLength: DensityToken.sendFailureSpacing)
            Button("Retry", action: retry)
                .linkButtonStyle()
            if let openThread {
                Button("Open Thread", action: openThread)
                    .linkButtonStyle()
            }
            Button("Discard", action: discard)
                .linkButtonStyle()
        }
        .font(.footnote)
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
        .padding(.vertical, DensityToken.rowVerticalPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: DensityToken.threadReplyNoticeCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DensityToken.threadReplyNoticeCornerRadius)
                .strokeBorder(.separator)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    VStack {
        ThreadReplyNoticeView(retry: {}, openThread: {}, discard: {})
        ThreadReplyNoticeView(retry: {}, openThread: nil, discard: {})
    }
    .frame(width: 420)
    .padding()
}
