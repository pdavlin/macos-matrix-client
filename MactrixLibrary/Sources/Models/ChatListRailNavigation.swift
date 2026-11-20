import Foundation

/// One item of the sidebar rail (MATRIX-217): what it selects and its name.
public struct ChatListRailItem: Equatable, Sendable {
    /// The filter a click on the item selects.
    public var filter: ChatListRailFilter
    /// The item's title, as the rail shows it: "Inbox", or the space's or
    /// the label's name.
    public var name: String

    public init(filter: ChatListRailFilter, name: String) {
        self.filter = filter
        self.name = name
    }
}

/// The Go menu's rail keys (MATRIX-217): ⌘1…⌘9 select a rail item, and
/// ⇧⌘] and ⇧⌘[ select the next and previous item.
public enum ChatListRailNavigation {
    /// ⌘1…⌘9.
    public static let shortcutCount = 9

    /// The rail's items in the order the rail shows them, top to bottom: the
    /// Inbox, then the spaces, then the labels.
    ///
    /// - Parameters:
    ///   - spaces: the rail's space items, in rail order
    ///     (`ChatListRailSpace.items`).
    ///   - labels: the labels, in document order.
    public static func items(spaces: [ChatListRailSpace], labels: [ChatLabel]) -> [ChatListRailItem] {
        [ChatListRailItem(filter: .inbox, name: "Inbox")]
            + spaces.map { ChatListRailItem(filter: .space($0.id), name: $0.name) }
            + labels.map { ChatListRailItem(filter: .label($0.id), name: $0.name) }
    }

    /// The items ⌘1…⌘9 select: element `n` is ⌘(n+1). ⌘1 is always the
    /// Inbox. Fewer items than keys gives a shorter array; the extra keys
    /// select nothing.
    public static func shortcutTargets(in items: [ChatListRailItem]) -> [ChatListRailItem] {
        Array(items.prefix(shortcutCount))
    }

    /// The item ⇧⌘] selects: the one after `selection`.
    ///
    /// From the last item it goes to the first, as Safari's tab keys do.
    /// A selection that is not in `filters` gives the first item. `nil`
    /// when no other item is there to select.
    ///
    /// - Parameters:
    ///   - selection: the rail's selected item, after
    ///     `ChatListRailFilter.resolved(labels:spaceIds:)`.
    ///   - filters: the rail's items in rail order.
    public static func next(after selection: ChatListRailFilter, in filters: [ChatListRailFilter]) -> ChatListRailFilter? {
        guard let index = filters.firstIndex(of: selection) else { return filters.first }
        let next = filters[(index + 1) % filters.count]
        return next == selection ? nil : next
    }

    /// The item ⇧⌘[ selects: the one before `selection`.
    ///
    /// From the first item it goes to the last. A selection that is not in
    /// `filters` gives the last item. `nil` when no other item is there to
    /// select.
    ///
    /// The parameters are those of `next(after:in:)`.
    public static func previous(before selection: ChatListRailFilter, in filters: [ChatListRailFilter]) -> ChatListRailFilter? {
        guard let index = filters.firstIndex(of: selection) else { return filters.last }
        let previous = filters[(index + filters.count - 1) % filters.count]
        return previous == selection ? nil : previous
    }
}
