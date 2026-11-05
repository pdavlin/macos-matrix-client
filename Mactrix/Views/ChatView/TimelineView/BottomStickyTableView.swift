import AppKit

/// The table's commands on the whole-message selection (MATRIX-113).
@MainActor
protocol TimelineMessageSelectionCommands: AnyObject {
    /// Whether at least one message is selected.
    var hasMessageSelection: Bool { get }
    /// Copies the selected messages as a plain-text transcript.
    func copyMessageSelection()
    /// Ends the message selection.
    func clearMessageSelection()
}

/// The timeline's table: unflipped, so rows stack from the bottom up.
///
/// Moved out of `TimelineTableView.swift` by MATRIX-113, which added the
/// message-selection commands below.
class BottomStickyTableView: NSTableView {
    /// Called once when a window live resize finishes, so the controller can
    /// settle heights for rows that were offscreen during the resize.
    var onLiveResizeEnd: (() -> Void)?

    /// Handles ⌘C and Esc while a message selection exists (MATRIX-113).
    ///
    /// A gutter click makes the table the first responder, so Edit > Copy
    /// (⌘C) reaches `copy(_:)` here. A click on message text moves the first
    /// responder into that row, so ⌘C then copies the selected text as
    /// before, and never reaches the table.
    weak var messageSelectionCommands: TimelineMessageSelectionCommands?

    // By returning false, the table starts drawing from the bottom up
    override var isFlipped: Bool {
        return false
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        onLiveResizeEnd?()
    }

    // MARK: - Message selection (MATRIX-113)

    /// Edit > Copy (⌘C): the transcript of the message selection.
    @objc func copy(_: Any?) {
        messageSelectionCommands?.copyMessageSelection()
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return messageSelectionCommands?.hasMessageSelection ?? false
        }
        return super.validateUserInterfaceItem(item)
    }

    /// Menu items ask this first when the target answers it, so the Copy
    /// rule holds even if AppKit's table checks menu items on its own.
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        validateUserInterfaceItem(menuItem)
    }

    /// Esc ends the message selection. Without one, the key goes to
    /// NSTableView as before. Matched in `keyDown(with:)`, before NSTableView's
    /// own key handling can take it.
    override func keyDown(with event: NSEvent) {
        let commands = messageSelectionCommands
        if event.charactersIgnoringModifiers == Self.escape, let commands, commands.hasMessageSelection {
            commands.clearMessageSelection()
            return
        }
        super.keyDown(with: event)
    }

    private static let escape = "\u{1B}"
}
