import SwiftUI

#if canImport(AppKit)
    public struct AttributedTextView: NSViewRepresentable {
        public let attributedString: NSAttributedString

        public init(attributedString: NSAttributedString) {
            self.attributedString = attributedString.trimmed
        }

        public func makeNSView(context _: Context) -> NSTextField {
            let textField = NSTextField(labelWithAttributedString: attributedString)

            textField.isEditable = false
            textField.isSelectable = true
            textField.allowsEditingTextAttributes = true

            textField.lineBreakStrategy = .standard
            textField.lineBreakMode = .byWordWrapping
            textField.usesSingleLineMode = false

            return textField
        }

        public func updateNSView(_ textField: NSTextField, context _: Context) {
            if textField.attributedStringValue != attributedString {
                textField.attributedStringValue = attributedString
            }
        }

        public func sizeThatFits(_ proposal: ProposedViewSize, nsView textField: NSTextField, context _: Context) -> CGSize? {
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
    var trimmed: NSAttributedString {
        let nonWhitespaces = CharacterSet.whitespacesAndNewlines.inverted
        let startRange = string.rangeOfCharacter(from: nonWhitespaces)
        let endRange = string.rangeOfCharacter(from: nonWhitespaces, options: .backwards)
        guard let startLocation = startRange?.upperBound, let endLocation = endRange?.lowerBound else {
            return self
        }
        let location = string.distance(from: string.startIndex, to: startLocation) - 1
        let length = string.distance(from: startLocation, to: endLocation) + 2
        let range = NSRange(location: location, length: length)

        return attributedSubstring(from: range)
    }
}
