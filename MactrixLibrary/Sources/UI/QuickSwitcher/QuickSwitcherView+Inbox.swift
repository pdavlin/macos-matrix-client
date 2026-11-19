import Models
import SwiftUI

// MATRIX-206, MATRIX-207: Archive, Snooze, and Remind Me Later in ⌘K.

/// The inbox actions ⌘K offers on a room row: the context menu of the row
/// menus (`InboxMenuContent`), and ⌘E on the highlighted row.
public struct QuickSwitcherInboxActions {
    /// The list a room's chat shows in.
    let placement: @MainActor (_ roomId: String) -> InboxPlacement
    /// The reminder of a room's chat, if it has one.
    let remindAt: @MainActor (_ roomId: String) -> Date?
    /// Runs a menu item for a room's chat.
    let perform: @MainActor (_ roomId: String, _ action: InboxMenuAction) -> Void

    public init(
        placement: @escaping @MainActor (_ roomId: String) -> InboxPlacement,
        remindAt: @escaping @MainActor (_ roomId: String) -> Date?,
        perform: @escaping @MainActor (_ roomId: String, _ action: InboxMenuAction) -> Void
    ) {
        self.placement = placement
        self.remindAt = remindAt
        self.perform = perform
    }
}

extension QuickSwitcherView {
    /// The inbox items for a room row. The sheet closes after an item, and
    /// the window shows the note with Undo.
    func inboxMenu(roomId: String, inbox: QuickSwitcherInboxActions) -> some View {
        InboxMenuContent(
            placement: inbox.placement(roomId),
            remindAt: inbox.remindAt(roomId),
            isEditable: true
        ) { action in
            inbox.perform(roomId, action)
            close()
        }
    }

    /// ⌘E: archives the highlighted room, or unarchives it when it is
    /// archived. A person row does nothing.
    func toggleArchiveOfHighlighted() {
        guard let inbox = actions.inbox else { return }
        let results = results
        guard let id = effectiveHighlightId(in: results),
              case let .room(room) = results.first(where: { $0.id == id })
        else { return }
        inbox.perform(room.id, inbox.placement(room.id) == .archived ? .unarchive : .archive)
        close()
    }
}
