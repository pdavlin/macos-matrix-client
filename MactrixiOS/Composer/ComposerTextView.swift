import SwiftUI
import UIKit

/// The composer's multiline field (MATRIX-86): a `UITextView` that grows with
/// its text up to `maxLines`, then scrolls.
///
/// Return inserts a newline, the iOS convention; the send button sends.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var maxLines = 6
    /// A count that the owner raises to put the keyboard focus in the field
    /// (MATRIX-245: "Reply in Thread"). Each new value takes the focus once.
    /// A value other than 0 at creation takes the focus when the field
    /// reaches the window.
    var focusRequest = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> ComposerFocusableTextView {
        let textView = ComposerFocusableTextView()
        textView.delegate = context.coordinator
        textView.font = .preferredFont(forTextStyle: .body)
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.returnKeyType = .default
        textView.accessibilityLabel = placeholder
        textView.accessibilityIdentifier = "composerText"
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textView
    }

    func updateUIView(_ textView: ComposerFocusableTextView, context: Context) {
        context.coordinator.text = $text
        if textView.text != text {
            textView.text = text
        }
        if context.coordinator.handledFocusRequest != focusRequest {
            context.coordinator.handledFocusRequest = focusRequest
            textView.requestFocus()
        }
    }

    /// The text's height at `width`, capped at `maxLines`. Past the cap the
    /// view scrolls inside its fixed height.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: ComposerFocusableTextView, context _: Context) -> CGSize? {
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let fitting = textView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let lineHeight = textView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        let cap = ceil(lineHeight * CGFloat(maxLines)) + textView.textContainerInset.top + textView.textContainerInset.bottom
        let scrolls = fitting.height > cap
        if textView.isScrollEnabled != scrolls {
            textView.isScrollEnabled = scrolls
        }
        return CGSize(width: width, height: min(ceil(fitting.height), cap))
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        /// The last `focusRequest` the field took.
        var handledFocusRequest = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}

/// The composer's text view. It keeps a focus request made before it is in
/// a window, and takes the focus when it reaches one: the composer of a
/// pushed screen is not in a window at its first update (MATRIX-245).
final class ComposerFocusableTextView: UITextView {
    private var wantsFocus = false

    /// Takes the keyboard focus now, or when the view reaches a window.
    func requestFocus() {
        if window != nil {
            becomeFirstResponder()
        } else {
            wantsFocus = true
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard wantsFocus, window != nil else { return }
        wantsFocus = false
        becomeFirstResponder()
    }
}
