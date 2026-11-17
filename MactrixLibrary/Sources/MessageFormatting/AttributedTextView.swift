import SwiftUI

#if canImport(AppKit)
    public struct AttributedTextView: NSViewRepresentable {
        public let attributedString: NSAttributedString

        public init(attributedString: NSAttributedString) {
            self.attributedString = attributedString.trimmed
        }

        public func makeNSView(context _: Context) -> LinkCursorTextField {
            let textField = LinkCursorTextField(labelWithAttributedString: attributedString)

            textField.isEditable = false
            textField.isSelectable = true
            textField.allowsEditingTextAttributes = true

            textField.lineBreakStrategy = .standard
            textField.lineBreakMode = .byWordWrapping
            textField.usesSingleLineMode = false

            return textField
        }

        public func updateNSView(_ textField: LinkCursorTextField, context _: Context) {
            if textField.attributedStringValue != attributedString {
                textField.attributedStringValue = attributedString
            }
        }

        public func sizeThatFits(_ proposal: ProposedViewSize, nsView textField: LinkCursorTextField, context _: Context) -> CGSize? {
            guard let width = proposal.width, width > 0, width != .infinity else { return nil }

            textField.preferredMaxLayoutWidth = width
            guard let size = textField.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: CGFloat.greatestFiniteMagnitude)) else {
                return nil
            }

            return CGSize(width: ceil(size.width), height: ceil(size.height))
        }
    }

#elseif canImport(UIKit)
    /// The iOS twin of the AppKit view above, with the same public API. A
    /// non-editable `UITextView` keeps the text selectable and its links tappable,
    /// which a `UILabel` cannot do.
    public struct AttributedTextView: UIViewRepresentable {
        public let attributedString: NSAttributedString

        public init(attributedString: NSAttributedString) {
            self.attributedString = attributedString.trimmed
        }

        public func makeUIView(context _: Context) -> UITextView {
            let textView = UITextView()
            textView.attributedText = attributedString

            textView.isEditable = false
            textView.isSelectable = true
            textView.isScrollEnabled = false

            textView.backgroundColor = .clear
            textView.textContainerInset = .zero
            textView.textContainer.lineFragmentPadding = 0
            textView.textContainer.lineBreakMode = .byWordWrapping

            return textView
        }

        public func updateUIView(_ textView: UITextView, context _: Context) {
            if textView.attributedText != attributedString {
                textView.attributedText = attributedString
            }
        }

        public func sizeThatFits(_ proposal: ProposedViewSize, uiView textView: UITextView, context _: Context) -> CGSize? {
            guard let width = proposal.width, width > 0, width != .infinity else { return nil }

            let size = textView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: ceil(size.width), height: ceil(size.height))
        }
    }
#endif

extension NSAttributedString {
    /// The string without leading and trailing whitespace.
    ///
    /// The range is in UTF-16 units, which is what `NSRange` counts. A count
    /// of `Character`s is shorter by one for each emoji outside the BMP, and
    /// cut that many units off the end (MATRIX-162).
    var trimmed: NSAttributedString {
        let text = string as NSString
        let nonWhitespaces = CharacterSet.whitespacesAndNewlines.inverted
        let first = text.rangeOfCharacter(from: nonWhitespaces)
        let last = text.rangeOfCharacter(from: nonWhitespaces, options: .backwards)
        guard first.location != NSNotFound, last.location != NSNotFound else {
            return self
        }
        let end = last.location + last.length
        return attributedSubstring(from: NSRange(location: first.location, length: end - first.location))
    }
}
