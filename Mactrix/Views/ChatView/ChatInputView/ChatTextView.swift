import AppKit
import Models
import OSLog
import SwiftUI
import Tokens

struct ChatTextView: NSViewRepresentable {
    typealias NSViewRepresentableType = NSTextView

    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize

    let text: Binding<String>
    let placeholder: String
    let disabled: Bool
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> DynamicTextView {
        let textView = DynamicTextView()

        textView.onSubmit = onSubmit

        textView.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: CGFloat(fontSize))
            ]
        )

        textView.backgroundColor = .clear
        textView.drawsBackground = false

        context.coordinator.textView = textView
        textView.delegate = context.coordinator

        textView.textContainerInset = DynamicTextView.padding

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        unsafe textView.textContainer?.widthTracksTextView = true

        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)

        textView.font = NSFont.systemFont(ofSize: CGFloat(fontSize))

        return textView
    }

    func updateNSView(_ textView: DynamicTextView, context: Context) {
        context.coordinator.text = text

        textView.onSubmit = onSubmit

        if textView.string != text.wrappedValue {
            textView.string = text.wrappedValue
            textView.invalidateIntrinsicContentSize()
        }

        let currentPlaceholderFont =
            textView.placeholderAttributedString?
                .attribute(
                    .font,
                    at: 0,
                    effectiveRange: nil
                ) as? NSFont
        let placeholderFontChanged =
            currentPlaceholderFont?.pointSize != CGFloat(fontSize)
        if textView.placeholderAttributedString?.string != placeholder ||
            placeholderFontChanged
        {
            textView.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: CGFloat(fontSize))
                ]
            )
        }

        if textView.isEditable != !disabled {
            textView.isEditable = !disabled
            textView.isSelectable = !disabled
            textView.alphaValue = !disabled ? 1.0 : 0.5

            if disabled {
                // resign first responder
                unsafe textView.window?.makeFirstResponder(nil)
            }
        }

        let currentFont = NSFont.systemFont(ofSize: CGFloat(fontSize))
        if textView.font?.pointSize != currentFont.pointSize {
            textView.font = currentFont
            textView.invalidateIntrinsicContentSize()
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(text: text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_: Notification) {
            guard let textView else { return }

            text.wrappedValue = textView.string
        }
    }
}

class DynamicTextView: NSTextView {
    @objc var placeholderAttributedString: NSAttributedString?

    static let padding = NSSize(width: 10, height: 10)

    var onSubmit: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        guard let container = unsafe textContainer, let manager = unsafe layoutManager else {
            return .zero
        }

        // Force the layout for the current width
        manager.ensureLayout(for: container)
        let usedRect = manager.usedRect(for: container)

        // Return a flexible width but a fixed height based on text
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height) + CGFloat(2 * Self.padding.height))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let oldWidth = frame.width
        super.setFrameSize(newSize)

        if oldWidth != newSize.width {
            invalidateIntrinsicContentSize()
        }
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    /// Maps a key event onto the composer's Return-key policy (decision D-1:
    /// Enter sends, Shift-Enter inserts a newline, Cmd-Enter also sends).
    /// The rule itself lives in `Models.ComposerKeyDecision` so it is
    /// unit-tested; this only translates the AppKit event.
    private func sendAction(for event: NSEvent) -> ComposerKeyDecision.Action {
        let isReturnKey = event.specialKey == .enter || event.specialKey == .carriageReturn
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return ComposerKeyDecision.action(
            isReturnKey: isReturnKey,
            hasMarkedText: hasMarkedText(),
            shift: modifiers.contains(.shift),
            command: modifiers.contains(.command),
            otherModifiers: !modifiers.subtracting([.shift, .command]).isEmpty
        )
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Cmd-enter arrives as a key equivalent, not through keyDown.
        let hasCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        if hasCommand, sendAction(for: event) == .send {
            onSubmit?()
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if sendAction(for: event) == .send {
            onSubmit?()
            return
        }

        // Passthrough: newline on Shift-Enter, IME composition commit, and
        // every non-Return key.
        super.keyDown(with: event)
    }
}
