import Core
import Models
import SwiftUI
import UI

/// The Edit menu's message section (MATRIX-108, M2-B1).
///
/// It acts on the message the pointer last entered, or the message the
/// timeline last focused, in the key window's room. The items come from the
/// same `MessageActionModel` as the right-click menu and the hover row, and
/// each item runs through the row's own `perform(_:)`.
///
/// The list does not change shape between messages: an action that does not
/// apply to the target shows disabled. With no room or no target, every item
/// is disabled. While messages are selected (MATRIX-113), the selected message
/// is the target and "Copy Messages" shows. It has no shortcut of its own:
/// the standard Copy (⌘C) copies the message selection when the timeline has
/// the keyboard focus, and a text selection when the text has it.
struct MessageCommands: Commands {
    @FocusedValue(WindowState.self) private var windowState: WindowState?

    /// The key window's room timeline, if a joined room is open.
    private var timeline: LiveTimeline? {
        guard case let .joinedRoom(timeline: timeline) = windowState?.selectedScreen else { return nil }
        return timeline
    }

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            UI.MessageActionMenu(
                items: timeline?.messageActionTarget.editMenuItems ?? MessageActionModel.items(for: nil, on: .editMenu),
                perform: { action in timeline?.messageActionTarget.perform(action) }
            )
        }
    }
}
