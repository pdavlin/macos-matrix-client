import Foundation

/// The short note a window shows after an inbox action, with its Undo
/// (MATRIX-206): "Archived Alice · Undo".
public struct InboxNotice: Identifiable, Equatable, Sendable {
    /// How long the note stays.
    public static let duration: Duration = .seconds(6)

    /// New for each action, so a second action restarts the timer.
    public let id: UUID
    /// The note's text.
    public var message: String
    /// The states the action replaced, by room ID. Undo writes them back.
    public var undoStates: [String: InboxRoomState]

    public init(id: UUID = UUID(), message: String, undoStates: [String: InboxRoomState]) {
        self.id = id
        self.message = message
        self.undoStates = undoStates
    }

    /// The note after archiving the chat named `chatName`.
    public static func archived(_ chatName: String, undoStates: [String: InboxRoomState]) -> InboxNotice {
        InboxNotice(message: "Archived \(chatName)", undoStates: undoStates)
    }
}
