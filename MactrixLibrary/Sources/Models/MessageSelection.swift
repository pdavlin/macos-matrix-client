import Foundation

/// What a click in a message's selection gutter does (MATRIX-113, M2-B6, D-2).
///
/// The gutter is the timestamp column at the leading edge of a message. A
/// click there selects whole messages; a click on the message text still
/// selects characters, so the two never compete for one gesture.
public enum MessageSelectionGesture: Equatable, Sendable {
    /// A plain click: the clicked message becomes the whole selection.
    case select
    /// A Shift-click: the selection becomes the range from the anchor to the
    /// clicked message.
    case extend
    /// A Command-click: the clicked message joins or leaves the selection.
    case toggle

    /// The gesture for a click with the given modifier keys. Command wins
    /// over Shift, as in Finder.
    ///
    /// - Parameters:
    ///   - isShiftDown: Whether Shift was down at the click.
    ///   - isCommandDown: Whether Command was down at the click.
    public init(isShiftDown: Bool, isCommandDown: Bool) {
        if isCommandDown {
            self = .toggle
        } else if isShiftDown {
            self = .extend
        } else {
            self = .select
        }
    }
}

/// The whole messages selected in one timeline (MATRIX-113, M2-B6, D-2).
///
/// Messages are named by their row identity (the SDK item's unique ID), so a
/// selection survives rows that insert or move around it and a local echo
/// that gets its event ID. The value knows nothing about the table: every
/// gesture takes the timeline's current message order as an input.
///
/// Usage:
/// ```swift
/// var selection = MessageSelection()
/// selection.apply(.select, to: "b", order: ["a", "b", "c"])
/// selection.apply(.extend, to: "c", order: ["a", "b", "c"]) // b and c
/// ```
public struct MessageSelection: Equatable, Sendable {
    /// The selected row IDs.
    public private(set) var selectedIds: Set<String> = []
    /// The message a Shift-click extends from: the last message that a plain
    /// click selected or a Command-click added. Nil when there is none.
    public private(set) var anchorId: String?

    public init() {}

    /// Whether no message is selected.
    public var isEmpty: Bool {
        selectedIds.isEmpty
    }

    /// Whether the message `id` is selected.
    public func contains(_ id: String) -> Bool {
        selectedIds.contains(id)
    }

    /// Changes the selection for one gesture on one message.
    ///
    /// - Parameters:
    ///   - gesture: The click kind.
    ///   - id: The row ID of the clicked message.
    ///   - order: The row IDs of every selectable message, in one consistent
    ///     timeline order. The direction does not matter; Shift-click reads
    ///     only the positions between the anchor and `id`.
    public mutating func apply(_ gesture: MessageSelectionGesture, to id: String, order: [String]) {
        switch gesture {
        case .select:
            selectOnly(id)
        case .extend:
            guard let anchorId,
                  let anchorIndex = order.firstIndex(of: anchorId),
                  let clickedIndex = order.firstIndex(of: id)
            else {
                // Nothing to extend from: a Shift-click starts a selection.
                selectOnly(id)
                return
            }
            let range = min(anchorIndex, clickedIndex) ... max(anchorIndex, clickedIndex)
            selectedIds = Set(order[range])
        case .toggle:
            if selectedIds.contains(id) {
                selectedIds.remove(id)
                if anchorId == id { anchorId = nil }
            } else {
                selectedIds.insert(id)
                anchorId = id
            }
        }
    }

    /// Clears the selection and its anchor.
    public mutating func clear() {
        selectedIds = []
        anchorId = nil
    }

    /// Drops the messages that left the timeline.
    ///
    /// - Parameter existingIds: The row IDs the timeline still has.
    /// - Returns: Whether the selection changed.
    @discardableResult
    public mutating func retain(_ existingIds: Set<String>) -> Bool {
        let kept = selectedIds.intersection(existingIds)
        let keptAnchor = anchorId.flatMap { existingIds.contains($0) ? $0 : nil }
        guard kept != selectedIds || keptAnchor != anchorId else { return false }
        selectedIds = kept
        anchorId = keptAnchor
        return true
    }

    private mutating func selectOnly(_ id: String) {
        selectedIds = [id]
        anchorId = id
    }
}
