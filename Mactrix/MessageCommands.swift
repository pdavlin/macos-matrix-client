import Core
import Models
import SwiftUI
import UI

/// The Edit menu's message section (MATRIX-108, M2-B1).
///
/// It acts on the message the pointer last entered, or the message the
/// timeline last focused, in the key window's room or merged chat. In a
/// merged chat (MATRIX-149) every member timeline shares one slot, so the
/// target is one message of the whole chat, and its action runs on the
/// member room that holds it. The items come from the same `MessageActionModel` as the right-click menu and the hover row, and
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

    /// The slot of the merged chat the key window shows. `MergedChatView`
    /// publishes it, because the window state holds only the merged chat's ID.
    @FocusedValue(MessageActionTargetSlot.self) private var mergedChatTarget: MessageActionTargetSlot?

    /// The Edit-menu target of the key window: the room timeline's slot, or
    /// the merged chat's slot. Nil on any other screen.
    private var target: MessageActionTargetSlot? {
        switch windowState?.selectedScreen {
        case let .joinedRoom(timeline: timeline):
            timeline.messageActionTarget
        case .mergedChat:
            mergedChatTarget
        default:
            nil
        }
    }

    var body: some Commands {
        CommandGroup(after: .pasteboard) {
            Divider()
            UI.MessageActionMenu(
                items: target?.editMenuItems ?? MessageActionModel.items(for: nil, on: .editMenu),
                perform: { action in target?.perform(action) }
            )
        }
    }
}
