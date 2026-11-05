import AppKit
import Models
import OSLog
import SwiftUI
import Tokens
import UI
import UniformTypeIdentifiers

struct ChatTextView: NSViewRepresentable {
    typealias NSViewRepresentableType = NSTextView

    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize
    @AppStorage(ComposerKeyDecision.SendMode.storageKey) var sendMode = ComposerKeyDecision.SendMode.defaultMode

    /// The composer content as draft text: typed text, and each mention chip
    /// as a `matrix.to` pill link (`Models.MentionMarkdown`). The text view
    /// shows the pills as chips.
    let text: Binding<String>
    let placeholder: String
    let disabled: Bool
    /// Runs the "@" autocomplete and inserts chips (MATRIX-105).
    let mentions: ComposerMentionController
    /// Takes pasted and dropped files and images, and removes the newest
    /// attachment on Esc (MATRIX-106).
    let attachments: ComposerAttachmentController
    /// False in edit mode: paste, drop, and Esc then leave the attachments
    /// alone (MATRIX-109).
    var attachmentsEnabled = true
    /// The Up arrow in an empty composer. Returns true if it started an edit
    /// (MATRIX-109).
    var onEmptyUpArrow: () -> Bool = { false }
    /// Esc when the mention popup and the attachments did not use it.
    /// Returns true if it cancelled edit mode (MATRIX-109).
    var onEscape: () -> Bool = { false }
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> DynamicTextView {
        // TextKit 1 on purpose: the mention chip cell draws through
        // NSLayoutManager, and `intrinsicContentSize` already uses it (an
        // access that would switch a TextKit 2 view to TextKit 1 anyway).
        let textView = DynamicTextView(usingTextLayoutManager: false)

        textView.onSubmit = onSubmit
        textView.sendMode = sendMode
        textView.mentionKeyHandler = { [weak mentions] key in
            mentions?.handle(key) ?? false
        }
        mentions.textView = textView
        configureAttachmentHandlers(of: textView)
        configureEditHandlers(of: textView)
        // Adds the file and image drag types (`acceptableDragTypes`).
        textView.updateDragTypeRegistration()

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
        context.coordinator.mentions = mentions

        textView.onSubmit = onSubmit
        textView.sendMode = sendMode
        textView.mentionKeyHandler = { [weak mentions] key in
            mentions?.handle(key) ?? false
        }
        mentions.textView = textView
        configureAttachmentHandlers(of: textView)
        configureEditHandlers(of: textView)

        let currentFont = NSFont.systemFont(ofSize: CGFloat(fontSize))
        if textView.font?.pointSize != currentFont.pointSize {
            textView.font = currentFont
            textView.invalidateIntrinsicContentSize()
        }

        // Rebuild only for a change from outside the text view (draft load,
        // clear after send). The view's own edits set `lastText` first.
        if text.wrappedValue != context.coordinator.lastText {
            context.coordinator.lastText = text.wrappedValue
            let segments = MentionMarkdown.segments(fromDraftText: text.wrappedValue)
            unsafe textView.textStorage?.setAttributedString(
                ComposerAttributedText.attributedString(for: segments, attributes: textView.baseTextAttributes)
            )
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
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
    }

    /// Points the text view's paste, drop, and Esc hooks at the attachment
    /// controller (MATRIX-106).
    private func configureAttachmentHandlers(of textView: DynamicTextView) {
        let isEnabled = attachmentsEnabled
        textView.attachmentContentHandler = { [weak attachments] pasteboard in
            isEnabled && attachments?.takeContent(of: pasteboard) ?? false
        }
        textView.attachmentDropFilter = { [weak attachments] pasteboard in
            isEnabled && attachments?.acceptsDrop(of: pasteboard) ?? false
        }
        textView.attachmentEscapeHandler = { [weak attachments] in
            isEnabled && attachments?.removeLast() ?? false
        }
    }

    /// Points the text view's Up-arrow and Esc hooks at the composer's edit
    /// mode (MATRIX-109).
    private func configureEditHandlers(of textView: DynamicTextView) {
        textView.emptyUpArrowHandler = onEmptyUpArrow
        textView.escapeHandler = onEscape
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(text: text, mentions: mentions)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var textView: NSTextView?
        var text: Binding<String>
        var mentions: ComposerMentionController

        /// The draft text the text view shows. `updateNSView` compares the
        /// binding with this, so it rebuilds the text only for an outside
        /// change and never for the view's own edit.
        var lastText = ""

        init(text: Binding<String>, mentions: ComposerMentionController) {
            self.text = text
            self.mentions = mentions
        }

        func textDidChange(_: Notification) {
            guard let textView, let storage = unsafe textView.textStorage else { return }

            let draftText = MentionMarkdown.draftText(for: ComposerAttributedText.segments(from: storage))
            lastText = draftText
            text.wrappedValue = draftText
            mentions.refresh()
        }

        func textViewDidChangeSelection(_: Notification) {
            mentions.refresh()
        }
    }
}

class DynamicTextView: NSTextView {
    @objc var placeholderAttributedString: NSAttributedString?

    static let padding = NSSize(width: 10, height: 10)

    var onSubmit: (() -> Void)?

    /// The user's Return-key send mode (Settings > Composer). Pushed in by
    /// `ChatTextView` from `@AppStorage`, so a change in Settings applies to
    /// open composers without a relaunch.
    var sendMode: ComposerKeyDecision.SendMode = .defaultMode

    /// Takes the popup keys (arrows, Return, Tab, Esc) while the mention
    /// popup is open. Returns true if it used the key (MATRIX-105).
    var mentionKeyHandler: ((MentionAutocompleteKey) -> Bool)?

    /// Takes the files or the image on a pasteboard as attachments, for a
    /// paste or a drop. Returns true if it took them; false lets the text
    /// view paste text as usual (MATRIX-106).
    var attachmentContentHandler: ((NSPasteboard) -> Bool)?

    /// Returns true if a drag holds files or an image that
    /// `attachmentContentHandler` takes (MATRIX-106).
    var attachmentDropFilter: ((NSPasteboard) -> Bool)?

    /// Removes the newest pending attachment on Esc. Returns true if it
    /// removed one (MATRIX-106).
    var attachmentEscapeHandler: (() -> Bool)?

    /// Runs on the Up arrow with no modifier while the text view is empty.
    /// Returns true if it started an edit of the last own message
    /// (MATRIX-109).
    var emptyUpArrowHandler: (() -> Bool)?

    /// Runs on Esc when the mention popup and the attachments did not use
    /// it. Returns true if it cancelled edit mode (MATRIX-109).
    var escapeHandler: (() -> Bool)?

    /// The pasteboard type for composer content with chips: the draft text
    /// (`MentionMarkdown.draftText(for:)`). Copy and paste inside the composer
    /// keep chips through it. Other apps get plain text.
    static let draftTextPasteboardType = NSPasteboard.PasteboardType("io.davlin.matrixclient.composer-draft-text")

    /// The font and color for typed text and chips.
    var baseTextAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: textColor ?? NSColor.textColor
        ]
    }

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

    /// Maps a key event onto the composer's Return-key policy for the current
    /// `sendMode` (default D-1: Enter sends, Shift-Enter inserts a newline,
    /// Cmd-Enter also sends). The rule itself lives in
    /// `Models.ComposerKeyDecision` so it is unit-tested; this only
    /// translates the AppKit event.
    private func sendAction(for event: NSEvent) -> ComposerKeyDecision.Action {
        let isReturnKey = event.specialKey == .enter || event.specialKey == .carriageReturn
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return ComposerKeyDecision.action(
            isReturnKey: isReturnKey,
            hasMarkedText: hasMarkedText(),
            shift: modifiers.contains(.shift),
            command: modifiers.contains(.command),
            otherModifiers: !modifiers.subtracting([.shift, .command]).isEmpty,
            mode: sendMode
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

    /// Maps a key event to a mention popup key. Only keys with no modifier
    /// count, and never during IME composition.
    private func mentionKey(for event: NSEvent) -> MentionAutocompleteKey? {
        guard !hasMarkedText() else { return nil }
        let modifiers = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.numericPad, .function, .capsLock])
        guard modifiers.isEmpty else { return nil }
        switch event.specialKey {
        case .upArrow:
            return .up
        case .downArrow:
            return .down
        case .enter, .carriageReturn, .tab:
            return .confirm
        default:
            return event.keyCode == Self.escapeKeyCode ? .dismiss : nil
        }
    }

    /// `kVK_Escape`.
    private static let escapeKeyCode: UInt16 = 53

    override func keyDown(with event: NSEvent) {
        if let key = mentionKey(for: event), mentionKeyHandler?(key) == true {
            return
        }

        // Esc with the mention popup closed removes the newest attachment,
        // and then cancels edit mode.
        if mentionKey(for: event) == .dismiss, attachmentEscapeHandler?() == true || escapeHandler?() == true {
            return
        }

        // Up arrow in an empty composer edits the last own message.
        if mentionKey(for: event) == .up, string.isEmpty, emptyUpArrowHandler?() == true {
            return
        }

        if sendAction(for: event) == .send {
            onSubmit?()
            return
        }

        // Passthrough: newline on Shift-Enter (and on Enter in
        // `.commandEnterSends`), IME composition commit, and every
        // non-Return key.
        super.keyDown(with: event)
    }

    // MARK: - Pasteboard (MATRIX-105)

    /// Writes a selection that holds a chip as draft text (for this composer)
    /// and plain text with "@name" (for other apps). A selection with no chip
    /// uses the default behavior.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let range = selectedRange()
        guard range.length > 0, let storage = unsafe textStorage else {
            return super.writeSelection(to: pboard, types: types)
        }
        let segments = ComposerAttributedText.segments(from: storage.attributedSubstring(from: range))
        guard !MentionMarkdown.mentionedUserIds(in: segments).isEmpty else {
            return super.writeSelection(to: pboard, types: types)
        }
        pboard.declareTypes([Self.draftTextPasteboardType, .string], owner: nil)
        pboard.setString(MentionMarkdown.draftText(for: segments), forType: Self.draftTextPasteboardType)
        pboard.setString(MentionMarkdown.plainText(for: segments), forType: .string)
        return true
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [Self.draftTextPasteboardType] + super.readablePasteboardTypes
    }

    /// Pastes draft text from this composer with its chips. Other types use
    /// the default behavior.
    override func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard type == Self.draftTextPasteboardType, let draftText = pboard.string(forType: type) else {
            return super.readSelection(from: pboard, type: type)
        }
        let segments = MentionMarkdown.segments(fromDraftText: draftText)
        insertText(
            ComposerAttributedText.attributedString(for: segments, attributes: baseTextAttributes),
            replacementRange: selectedRange()
        )
        return true
    }

    // MARK: - Attachments (MATRIX-106)

    /// Pastes files and images as attachments. Text, and composer draft text
    /// with chips, paste as before.
    override func paste(_ sender: Any?) {
        if attachmentContentHandler?(NSPasteboard.general) == true {
            return
        }
        super.paste(sender)
    }

    /// Adds file URLs and image types, so a drop of files or images reaches
    /// `performDragOperation(_:)`.
    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL, .png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier)]
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if attachmentDropFilter?(sender.draggingPasteboard) == true {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if attachmentDropFilter?(sender.draggingPasteboard) == true {
            return .copy
        }
        return super.draggingUpdated(sender)
    }

    /// Drops files and images as attachments. A text drag drops as text.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if attachmentDropFilter?(sender.draggingPasteboard) == true {
            return attachmentContentHandler?(sender.draggingPasteboard) ?? false
        }
        return super.performDragOperation(sender)
    }
}
