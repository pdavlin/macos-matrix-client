import Models
import SwiftUI

// MATRIX-206: Archive and Unarchive in ⌘K.

/// The inbox actions ⌘K offers on a room row (MATRIX-206): a context menu,
/// and ⌘E on the highlighted row.
public struct QuickSwitcherInboxActions {
    /// The list a room's chat shows in.
    let placement: @MainActor (_ roomId: String) -> InboxPlacement
    /// Archives (true) or unarchives (false) a room's chat.
    let setArchived: @MainActor (_ roomId: String, _ archived: Bool) -> Void

    public init(
        placement: @escaping @MainActor (_ roomId: String) -> InboxPlacement,
        setArchived: @escaping @MainActor (_ roomId: String, _ archived: Bool) -> Void
    ) {
        self.placement = placement
        self.setArchived = setArchived
    }
}

extension QuickSwitcherView {
    /// Archive or Unarchive for a room row (MATRIX-206). The sheet closes
    /// after the action, and the window shows the note with Undo.
    @ViewBuilder
    func inboxMenu(roomId: String, inbox: QuickSwitcherInboxActions) -> some View {
        if inbox.placement(roomId) == .archived {
            Button("Unarchive") {
                inbox.setArchived(roomId, false)
                close()
            }
        } else {
            Button("Archive") {
                inbox.setArchived(roomId, true)
                close()
            }
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
        inbox.setArchived(room.id, inbox.placement(room.id) != .archived)
        close()
    }
}
