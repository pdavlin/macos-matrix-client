import Foundation

/// One line of a menu built from action items.
public enum MessageActionMenuEntry: Hashable, Sendable {
    /// A single menu item.
    case action(MessageActionItem)
    /// The quick reactions, drawn as one React submenu.
    case reactions([MessageActionItem])
    /// A separator between two sections.
    case separator
}

/// Turns ordered action items into menu lines: quick reactions fold into one
/// submenu, and a separator goes between two sections.
public enum MessageActionMenuLayout {
    /// - Parameter items: Items in display order, from `MessageActionModel`.
    /// - Returns: The menu lines, with no leading, trailing, or double separator.
    public static func entries(for items: [MessageActionItem]) -> [MessageActionMenuEntry] {
        var entries: [MessageActionMenuEntry] = []
        var previousSection: MessageActionSection?
        var pendingReactions: [MessageActionItem] = []

        func flushReactions() {
            guard !pendingReactions.isEmpty else { return }
            entries.append(.reactions(pendingReactions))
            pendingReactions = []
        }

        for item in items {
            if let previousSection, previousSection != item.section {
                flushReactions()
                entries.append(.separator)
            }
            previousSection = item.section
            if item.action.isQuickReaction {
                pendingReactions.append(item)
            } else {
                flushReactions()
                entries.append(.action(item))
            }
        }
        flushReactions()
        return entries
    }
}
