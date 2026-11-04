import AppKit
import Models
import Observation
import UI

/// Connects the composer text view to the mention popup (MATRIX-105, D-6).
///
/// This type is glue only. The rules live in `Models`: `MentionTrigger` finds
/// the open "@" query, `MentionSuggestionFilter` ranks the members, and
/// `MentionAutocompleteState` holds the rows and the selection. The chip
/// itself is `UI.MentionChipAttachment`.
///
/// `ChatInputView` owns one controller per composer. `ChatTextView` gives it
/// the text view and calls `refresh()` on each text or selection change.
@MainActor @Observable
final class ComposerMentionController {
    /// The open popup, or nil when it is closed. `ChatInputView` draws the
    /// rows from this.
    private(set) var state: MentionAutocompleteState?

    /// The composer text view. Weak, because the view owns its delegate
    /// chain and SwiftUI owns the view.
    @ObservationIgnored weak var textView: DynamicTextView?

    /// Returns the room members to offer. Read on each query change, so a
    /// member list update shows on the next keystroke.
    @ObservationIgnored var candidateProvider: () -> [MentionCandidate] = { [] }

    /// Users the popup never offers (the own user).
    @ObservationIgnored var excludedUserIds: Set<String> = []

    /// The UTF-16 location of the "@" whose popup the user closed with Esc.
    /// The popup stays closed for that "@" until the query ends.
    @ObservationIgnored private var dismissedTriggerLocation: Int?

    /// Opens, updates, or closes the popup for the text and caret in the text
    /// view. Call it after each text change and each selection change.
    func refresh() {
        guard let textView else {
            state = nil
            return
        }
        let selection = textView.selectedRange()
        let caret = selection.length == 0 && !textView.hasMarkedText() ? selection.location : nil
        guard let trigger = MentionTrigger.find(in: textView.string, caret: caret) else {
            dismissedTriggerLocation = nil
            state = nil
            return
        }
        guard trigger.range.location != dismissedTriggerLocation else {
            state = nil
            return
        }
        // A selection change with the same query keeps the selected row.
        if state?.trigger == trigger { return }

        let suggestions = MentionSuggestionFilter.suggestions(
            for: trigger.query,
            in: candidateProvider(),
            excluding: excludedUserIds
        )
        state = MentionAutocompleteState(trigger: trigger, suggestions: suggestions)
    }

    /// Handles a popup key from the text view.
    ///
    /// - Parameter key: the key the user pressed.
    /// - Returns: true if the popup used the key. False when the popup is
    ///   closed, so the text view handles the key as usual.
    func handle(_ key: MentionAutocompleteKey) -> Bool {
        guard var current = state else { return false }
        switch key {
        case .up:
            current.moveSelection(by: -1)
            state = current
        case .down:
            current.moveSelection(by: 1)
            state = current
        case .confirm:
            pick(current.selected)
        case .dismiss:
            dismissedTriggerLocation = current.trigger.range.location
            state = nil
        }
        return true
    }

    /// Replaces the open "@" query with a chip for `candidate` and a space.
    ///
    /// - Parameter candidate: the row the user picked.
    func pick(_ candidate: MentionCandidate) {
        guard let textView, let state else { return }
        let length = (textView.string as NSString).length
        guard NSMaxRange(state.trigger.range) <= length else {
            self.state = nil
            return
        }
        insert(candidate.target, replacing: state.trigger.range, leadingSpace: false, in: textView)
    }

    /// Inserts a chip at the caret, for the user profile "Mention" action.
    /// Adds a space before the chip if the character before the caret is not
    /// whitespace, and focuses the composer.
    ///
    /// - Parameter target: the user to mention.
    func insertMention(_ target: MentionTarget) {
        guard let textView else { return }
        let range = textView.selectedRange()
        let text = textView.string as NSString
        var leadingSpace = false
        if range.location > 0, range.location <= text.length {
            let previous = text.character(at: range.location - 1)
            leadingSpace = !(Unicode.Scalar(previous).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false)
        }
        insert(target, replacing: range, leadingSpace: leadingSpace, in: textView)
        unsafe textView.window?.makeFirstResponder(textView)
    }

    /// Inserts the chip through `insertText`, so undo, the delegate, and the
    /// draft binding see a normal edit.
    private func insert(
        _ target: MentionTarget,
        replacing range: NSRange,
        leadingSpace: Bool,
        in textView: DynamicTextView
    ) {
        let attributes = textView.baseTextAttributes
        let insertion = NSMutableAttributedString()
        if leadingSpace {
            insertion.append(NSAttributedString(string: " ", attributes: attributes))
        }
        insertion.append(ComposerAttributedText.chip(for: target, attributes: attributes))
        insertion.append(NSAttributedString(string: " ", attributes: attributes))

        dismissedTriggerLocation = nil
        state = nil
        textView.insertText(insertion, replacementRange: range)
    }
}
