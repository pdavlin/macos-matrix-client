import Core
import Models
import UI

// MARK: - Message selection (MATRIX-113, M2-B6)

/// The row side of whole-message selection. The row does not keep the
/// selection: it reports gutter clicks to the timeline's action slot, and the
/// timeline container decides the result, because only the container knows
/// the row order a Shift-click needs.
extension ChatMessageView {
    /// Whether the timeline has a message selection. Read in the body, so a
    /// row redraws its menus when a selection starts or ends. A row redraw is
    /// not a re-measure: the menus do not change the row's layout.
    var hasMessageSelection: Bool {
        rowActions.hasMessageSelection
    }

    /// Reports a click in this message's selection gutter. Nil without a
    /// timeline, which leaves the gutter without a click target.
    var messageSelectionHandler: (@MainActor (MessageSelectionGesture) -> Void)? {
        guard let slot = timeline?.messageActionTarget else { return nil }
        return { gesture in
            slot.select(gesture, on: actionTarget)
        }
    }
}
