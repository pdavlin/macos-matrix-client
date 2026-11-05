import Foundation
import Observation

/// The message the Edit menu acts on, and how to act on it (MATRIX-108).
public struct MessageActionTarget {
    /// The row's event or transaction ID. A row withdraws only its own target.
    public let key: String
    public let subject: MessageActionSubject
    /// The quick reactions the menus offer, from the account's recent emoji
    /// (MATRIX-111).
    public let quickReactionKeys: [String]
    /// Runs an action on the message. The row that offered the target builds
    /// it, so the SDK call stays in the row's code path.
    public let perform: @MainActor (MessageAction) -> Void
    /// Whether the timeline had a message selection when the row built this
    /// target (MATRIX-113). The media menus read it to offer Copy Messages.
    public let hasMessageSelection: Bool

    public init(
        key: String,
        subject: MessageActionSubject,
        quickReactionKeys: [String] = MessageActionModel.defaultQuickReactionKeys,
        hasMessageSelection: Bool = false,
        perform: @escaping @MainActor (MessageAction) -> Void
    ) {
        self.key = key
        self.subject = subject
        self.quickReactionKeys = quickReactionKeys
        self.hasMessageSelection = hasMessageSelection
        self.perform = perform
    }

    /// The message's actions on `surface`, with this target's quick reactions.
    public func items(on surface: MessageActionSurface) -> [MessageActionItem] {
        MessageActionModel.items(
            for: subject,
            on: surface,
            quickReactionKeys: quickReactionKeys,
            hasMessageSelection: hasMessageSelection
        )
    }
}

/// Holds the Edit menu's target message for one timeline.
///
/// A row offers itself when the pointer enters it or when the timeline focuses
/// it. The target stays after the pointer leaves, so the person can move the
/// pointer to the menu bar and still act on that message. A row withdraws its
/// target when it leaves the screen.
///
/// Only `editMenuItems` is observable, and it changes only when the items
/// differ. The pointer moves over many rows while the timeline scrolls, and
/// rows of the same kind give the same items, so the menu bar rebuilds only
/// when the menu really changes. The target itself is not observed.
///
/// A message selection (MATRIX-113, M2-B6) comes before the hover: while
/// one exists, the Edit menu acts on the selected message, and the pointer
/// no longer moves the target. With more than one selected message, the
/// single-message items are disabled and Copy Messages copies them all.
///
/// The timeline container owns the selection itself (it knows the row
/// order). The slot is the meeting point: rows report gutter clicks through
/// `select(_:on:)`, and the container reports the result through
/// `showSelection(keys:copy:)`.
@MainActor @Observable
public final class MessageActionTargetSlot {
    /// The Edit-menu items for the current target, all disabled when there is
    /// no target.
    public private(set) var editMenuItems: [MessageActionItem] = MessageActionModel.items(for: nil, on: .editMenu)

    /// Whether the timeline has a message selection. Rows read it for their
    /// menus, so it changes only when a selection starts or ends, not on every
    /// selection change.
    public private(set) var hasMessageSelection = false

    /// The hovered or focused message.
    @ObservationIgnored public private(set) var target: MessageActionTarget?

    /// The selected message, while exactly one is selected and its row is on
    /// the screen.
    @ObservationIgnored public private(set) var selectedTarget: MessageActionTarget?

    /// The container's handler for a gutter click on the message `key`.
    @ObservationIgnored public var selectionGestureHandler: (@MainActor (_ key: String, _ gesture: MessageSelectionGesture) -> Void)?

    /// The row that reported the last gutter click. It becomes
    /// `selectedTarget` when the click leaves it as the only selected message.
    @ObservationIgnored private var gestureTarget: MessageActionTarget?
    /// Copies the selection as a transcript. Set by the container.
    @ObservationIgnored private var copySelectionAction: (@MainActor () -> Void)?

    public init() {}

    /// The message the Edit menu acts on: the selected message while a
    /// selection exists (nil with more than one), else the hovered one.
    public var editMenuTarget: MessageActionTarget? {
        hasMessageSelection ? selectedTarget : target
    }

    /// Makes `target` the Edit menu's message.
    public func offer(_ target: MessageActionTarget) {
        self.target = target
        publishItems()
    }

    /// Updates the target if it is still the message `key` names. A row calls
    /// this when its message changes, for example when a local echo gets its
    /// event ID, so the Edit menu does not act on old facts.
    public func refresh(replacing key: String, with target: MessageActionTarget) {
        if selectedTarget?.key == key { selectedTarget = target }
        if gestureTarget?.key == key { gestureTarget = target }
        guard self.target?.key == key else {
            publishItems()
            return
        }
        offer(target)
    }

    /// Clears the target if it is still the message `key` names. A selected
    /// message stays selected, but its single-message items are disabled
    /// until its row is back on the screen and clicked or hovered again.
    public func withdraw(key: String) {
        if gestureTarget?.key == key { gestureTarget = nil }
        if selectedTarget?.key == key { selectedTarget = nil }
        if target?.key == key { target = nil }
        publishItems()
    }

    /// Runs `action` on the Edit menu's target, or copies the selection.
    public func perform(_ action: MessageAction) {
        if action == .copyMessages {
            copySelection()
        } else {
            editMenuTarget?.perform(action)
        }
    }

    // MARK: - Message selection (MATRIX-113)

    /// Reports a gutter click on a row's message to the container.
    ///
    /// - Parameters:
    ///   - gesture: The click kind.
    ///   - target: The clicked row's message, as the row would offer it.
    public func select(_ gesture: MessageSelectionGesture, on target: MessageActionTarget) {
        gestureTarget = target
        selectionGestureHandler?(target.key, gesture)
    }

    /// Records the container's selection.
    ///
    /// - Parameters:
    ///   - keys: The event or transaction IDs of the selected messages. Empty
    ///     clears the selection.
    ///   - copy: Copies the selection as a transcript.
    public func showSelection(keys: [String], copy: @escaping @MainActor () -> Void) {
        guard let firstKey = keys.first else {
            clearSelection()
            return
        }
        copySelectionAction = copy
        selectedTarget = keys.count == 1
            ? [gestureTarget, target, selectedTarget].compactMap(\.self).first { $0.key == firstKey }
            : nil
        if !hasMessageSelection { hasMessageSelection = true }
        publishItems()
    }

    /// Ends the selection. The Edit menu goes back to the hovered message.
    public func clearSelection() {
        copySelectionAction = nil
        selectedTarget = nil
        if hasMessageSelection { hasMessageSelection = false }
        publishItems()
    }

    /// Copies the selection as a transcript, if there is a selection.
    public func copySelection() {
        copySelectionAction?()
    }

    private func publishItems() {
        let target = editMenuTarget
        let items = MessageActionModel.items(
            for: target?.subject,
            on: .editMenu,
            quickReactionKeys: target?.quickReactionKeys ?? MessageActionModel.defaultQuickReactionKeys,
            hasMessageSelection: hasMessageSelection
        )
        if items != editMenuItems {
            editMenuItems = items
        }
    }
}
