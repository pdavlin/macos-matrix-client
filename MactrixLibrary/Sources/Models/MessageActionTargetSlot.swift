import Foundation
import Observation

/// The message the Edit menu acts on, and how to act on it (MATRIX-108).
public struct MessageActionTarget {
    /// The row's event or transaction ID. A row withdraws only its own target.
    public let key: String
    public let subject: MessageActionSubject
    /// Runs an action on the message. The row that offered the target builds
    /// it, so the SDK call stays in the row's code path.
    public let perform: @MainActor (MessageAction) -> Void

    public init(key: String, subject: MessageActionSubject, perform: @escaping @MainActor (MessageAction) -> Void) {
        self.key = key
        self.subject = subject
        self.perform = perform
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
/// B6 (selection) makes a selected message the target before a hovered one.
@MainActor @Observable
public final class MessageActionTargetSlot {
    /// The Edit-menu items for the current target, all disabled when there is
    /// no target.
    public private(set) var editMenuItems: [MessageActionItem] = MessageActionModel.items(for: nil, on: .editMenu)

    @ObservationIgnored public private(set) var target: MessageActionTarget?

    public init() {}

    /// Makes `target` the Edit menu's message.
    public func offer(_ target: MessageActionTarget) {
        self.target = target
        publishItems()
    }

    /// Updates the target if it is still the message `key` names. A row calls
    /// this when its message changes, for example when a local echo gets its
    /// event ID, so the Edit menu does not act on old facts.
    public func refresh(replacing key: String, with target: MessageActionTarget) {
        guard self.target?.key == key else { return }
        offer(target)
    }

    /// Clears the target if it is still the message `key` names.
    public func withdraw(key: String) {
        guard target?.key == key else { return }
        target = nil
        publishItems()
    }

    /// Runs `action` on the target, if there is one.
    public func perform(_ action: MessageAction) {
        target?.perform(action)
    }

    private func publishItems() {
        let items = MessageActionModel.items(for: target?.subject, on: .editMenu)
        if items != editMenuItems {
            editMenuItems = items
        }
    }
}
