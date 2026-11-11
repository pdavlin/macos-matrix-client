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
/// It draws the whole-message selection behind the row's hosting view, and
/// the jump-to-message flash (MATRIX-136) in a subview below it. The
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

    // MARK: Jump-to-message flash (MATRIX-136)

    /// The flash wash, made on the first flash this row view shows. Most row
    /// views never flash, so they never pay for it.
    private var jumpFlashView: TimelineJumpFlashView?

    /// The wash covers the same rect as the selection background. A row
    /// view that is not sized yet gets its bounds, never a null rect.
    private var jumpFlashFrame: NSRect {
        let inset = DensityToken.rowHorizontalPadding
        guard bounds.width > inset * 2 else { return bounds }
        return bounds.insetBy(dx: inset, dy: 0)
    }

    /// The table sizes row views through their frame, so the wash follows
    /// here rather than in a layout pass that may not run.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        jumpFlashView?.frame = jumpFlashFrame
    }

    /// Shows the flash that started at `startTime`, `elapsed` seconds in.
    func showJumpFlash(startTime: TimeInterval, elapsed: TimeInterval) {
        let flashView: TimelineJumpFlashView
        if let jumpFlashView {
            flashView = jumpFlashView
        } else {
            flashView = TimelineJumpFlashView(frame: jumpFlashFrame)
            // Below the row's hosting view: the wash tints behind the content.
            addSubview(flashView, positioned: .below, relativeTo: nil)
            jumpFlashView = flashView
        }
        flashView.frame = jumpFlashFrame
        flashView.play(startTime: startTime, elapsed: elapsed)
    }

    /// Removes any flash, for a row view bound to a row that does not flash.
    func clearJumpFlash() {
        jumpFlashView?.stop()
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
    /// Connects the table's ⌘C and Esc, and the rows' gutter clicks. A
    /// merged chat's rows report through their member timeline's slot, so
    /// every room timeline of the source gets the handler (MATRIX-142).
    func installMessageSelection() {
        tableView.messageSelectionCommands = self
        #if canImport(Core)
            for timeline in source.actionTimelines {
                timeline.messageActionTarget.selectionGestureHandler = { [weak self] key, gesture in
                    self?.handleMessageSelectionGesture(gesture, onMessageKey: key)
                }
            }
        #endif
    }

    /// The row view for table row `row`, with its selection state.
    func makeMessageRowView(in tableView: NSTableView, forRow row: Int) -> NSTableRowView {
        let recycled = tableView.makeView(withIdentifier: TimelineMessageRowView.reuseIdentifier, owner: self)
        let rowView = recycled as? TimelineMessageRowView ?? TimelineMessageRowView()
        rowView.identifier = TimelineMessageRowView.reuseIdentifier
        rowView.isMessageSelected = isMessageSelected(atRow: row)
        applyJumpFlash(to: rowView, atRow: row)
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

        /// Tells the action slots what is selected, so the Edit menu and the
        /// row menus offer Copy Messages and act on the selected message. A
        /// merged chat's selection can span member rooms, so every member's
        /// slot gets the whole selection (MATRIX-142).
        func publishMessageSelection() {
            let slots = source.actionTimelines.map(\.messageActionTarget)
            guard !messageSelection.isEmpty else {
                for slot in slots {
                    slot.clearSelection()
                }
                return
            }
            let keys: [String] = timelineRows
                .filter { messageSelection.contains($0.uniqueId) }
                .compactMap { messageKey(of: $0) }
            for slot in slots {
                slot.showSelection(keys: keys) { [weak self] in
                    self?.copyMessageSelection()
                }
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
