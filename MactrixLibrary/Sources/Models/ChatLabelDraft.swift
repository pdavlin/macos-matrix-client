import Foundation

/// The editable state of the Create/Edit Label sheet (MATRIX-77).
public struct ChatLabelDraft: Equatable, Sendable {
    public var name: String
    public var colorIndex: Int?
    public var icon: String?
    /// Selected room IDs, in selection order.
    public var rooms: [String]

    public init(name: String = "", colorIndex: Int? = nil, icon: String? = nil, rooms: [String] = []) {
        self.name = name
        self.colorIndex = colorIndex
        self.icon = icon
        self.rooms = rooms
    }

    /// The draft for an existing label.
    public init(label: ChatLabel) {
        self.init(name: label.name, colorIndex: label.colorIndex, icon: label.icon, rooms: label.rooms)
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func isSelected(_ roomId: String) -> Bool {
        rooms.contains(roomId)
    }

    public mutating func toggle(_ roomId: String) {
        if let index = rooms.firstIndex(of: roomId) {
            rooms.remove(at: index)
        } else {
            rooms.append(roomId)
        }
    }

    /// Beeper's Save rule: a non-blank name, at least one chat, and a change
    /// from `original` (the sheet's starting draft). Room order and name
    /// padding are not changes.
    public func canSave(comparedTo original: ChatLabelDraft) -> Bool {
        guard !trimmedName.isEmpty, !rooms.isEmpty else { return false }
        return trimmedName != original.trimmedName
            || colorIndex != original.colorIndex
            || icon != original.icon
            || Set(rooms) != Set(original.rooms)
    }
}
