import AppKit
import MatrixRustSDK
import Models
import OSLog
import Tokens

// The timeline spike compiles this file without Core (see spike/GATE.md).
// Without Core there is no action slot, so no gutter click ever arrives and
// the selection stays empty; the row view and the highlight path still run.
#if canImport(Core)
    import Core
#endif

/// The row view behind every timeline row (MATRIX-113, M2-B6, D-2).
///
/// It draws the whole-message selection behind the row's hosting view. The
/// selection is drawn, not laid out: the tint never changes the row height,
/// and a selection change never touches the height cache or the MATRIX-63
/// fingerprints.
final class TimelineMessageRowView: NSTableRowView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("TimelineMessageRowView")

    /// Whether the row's message is in the message selection.
    var isMessageSelected = false {
        didSet {
            guard oldValue != isMessageSelected else { return }
            setAccessibilitySelected(isMessageSelected)
            needsDisplay = true
        }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard isMessageSelected else { return }
        // The same inset and corner as the hover background of the message.
        let rect = bounds.insetBy(dx: DensityToken.rowHorizontalPadding, dy: 0)
        NSColor.controlAccentColor.withAlphaComponent(CGFloat(AccentToken.selectionBackgroundOpacity)).setFill()
        NSBezierPath(roundedRect: rect, xRadius: BubbleToken.cornerRadius, yRadius: BubbleToken.cornerRadius).fill()
    }
}

// MARK: - Selection state and highlight

/// Whole-message selection (MATRIX-113, M2-B6, D-2).
///
/// A click in a message's gutter (its timestamp column) selects it,
/// Shift-click extends from the anchor, and Command-click toggles. The row
/// reports the click through the timeline's `MessageActionTargetSlot`; this
/// controller owns the selection, because only it knows the row order.
/// AppKit's own row selection stays off, so text, links, and media in a row
/// take clicks as before.
///
/// The selection clears on Esc, and with the room: each room gets a new
/// `LiveTimeline` and a new controller (`ChatView` is keyed by the room ID).
extension TimelineViewController: TimelineMessageSelectionCommands {
    /// Connects the table's ⌘C and Esc, and the rows' gutter clicks.
    func installMessageSelection() {
        tableView.messageSelectionCommands = self
        #if canImport(Core)
            timeline.messageActionTarget.selectionGestureHandler = { [weak self] key, gesture in
                self?.handleMessageSelectionGesture(gesture, onMessageKey: key)
            }
        #endif
    }

    /// The row view for table row `row`, with its selection state.
    func makeMessageRowView(in tableView: NSTableView, forRow row: Int) -> NSTableRowView {
        let recycled = tableView.makeView(withIdentifier: TimelineMessageRowView.reuseIdentifier, owner: self)
        let rowView = recycled as? TimelineMessageRowView ?? TimelineMessageRowView()
        rowView.identifier = TimelineMessageRowView.reuseIdentifier
        rowView.isMessageSelected = isMessageSelected(atRow: row)
        return rowView
    }

    var hasMessageSelection: Bool {
        !messageSelection.isEmpty
    }

    func clearMessageSelection() {
        guard !messageSelection.isEmpty else { return }
        messageSelection.clear()
        messageSelectionDidChange()
    }

    func copyMessageSelection() {
        #if canImport(Core)
            let transcript = messageSelectionTranscript()
            guard !transcript.isEmpty else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
            Logger.timelineTableView.debug("copied a transcript of \(self.messageSelection.selectedIds.count) message(s)")
        #endif
    }

    /// The row IDs of every message row, in display order. Only message rows
    /// take part in a selection: day dividers and state events do not.
    var selectableMessageIds: [String] {
        timelineRows.compactMap { row in
            guard case .message = row else { return nil }
            return row.uniqueId
        }
    }

    /// Drops selected messages that left the timeline, off the current view
    /// update pass. A no-op without a selection, so ordinary batches pay
    /// nothing.
    func scheduleMessageSelectionPrune() {
        guard !messageSelection.isEmpty, !messageSelectionPruneScheduled else { return }
        messageSelectionPruneScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            messageSelectionPruneScheduled = false
            if messageSelection.retain(Set(selectableMessageIds)) {
                messageSelectionDidChange()
            }
        }
    }

    /// Repaints the row views on the screen and reports the selection to the
    /// action slot.
    func messageSelectionDidChange() {
        tableView.enumerateAvailableRowViews { rowView, row in
            (rowView as? TimelineMessageRowView)?.isMessageSelected = isMessageSelected(atRow: row)
        }
        #if canImport(Core)
            publishMessageSelection()
        #endif
    }

    private func isMessageSelected(atRow row: Int) -> Bool {
        guard !messageSelection.isEmpty, timelineRows.indices.contains(row) else { return false }
        return messageSelection.contains(timelineRows[row].uniqueId)
    }
}

// MARK: - Gestures, menus, and the transcript

#if canImport(Core)
    extension TimelineViewController {
        /// Applies a gutter click on the message `key` (its event or
        /// transaction ID) and gives the table the keyboard focus, so ⌘C and
        /// Esc act on the selection.
        func handleMessageSelectionGesture(_ gesture: MessageSelectionGesture, onMessageKey key: String) {
            guard let row = timelineRows.first(where: { messageKey(of: $0) == key }) else {
                Logger.timelineTableView.error("selection gesture on a message with no row: \(key, privacy: .public)")
                return
            }
            messageSelection.apply(gesture, to: row.uniqueId, order: selectableMessageIds)
            view.window?.makeFirstResponder(tableView)
            messageSelectionDidChange()
        }

        /// Tells the action slot what is selected, so the Edit menu and the
        /// row menus offer Copy Messages and act on the selected message.
        func publishMessageSelection() {
            let slot = timeline.messageActionTarget
            guard !messageSelection.isEmpty else {
                slot.clearSelection()
                return
            }
            let keys: [String] = timelineRows
                .filter { messageSelection.contains($0.uniqueId) }
                .compactMap { messageKey(of: $0) }
            slot.showSelection(keys: keys) { [weak self] in
                self?.copyMessageSelection()
            }
        }

        /// The plain-text transcript of the selected messages, oldest first.
        func messageSelectionTranscript() -> String {
            let lines: [MessageTranscriptLine] = timelineRows.enumerated().compactMap { index, row in
                guard messageSelection.contains(row.uniqueId),
                      let event = sdkEvent(of: row),
                      case let .msgLike(content: msg) = event.content
                else { return nil }
                return MessageTranscriptLine(event: event, msg: msg, displayIndex: index)
            }
            return MessageTranscript.text(for: lines)
        }

        private func sdkEvent(of row: TimelineRow) -> MatrixRustSDK.EventTimelineItem? {
            guard case let .message(_, event, _, _) = row else { return nil }
            return event as? MatrixRustSDK.EventTimelineItem
        }

        /// The key the action slot names a message by: its event or
        /// transaction ID, as `ChatMessageView` reports it.
        private func messageKey(of row: TimelineRow) -> String? {
            sdkEvent(of: row)?.eventOrTransactionId.id
        }
    }
#endif
