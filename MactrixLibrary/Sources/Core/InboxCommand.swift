import Models

/// The key window's Archive command, for the File menu (⌘E, MATRIX-206).
///
/// MATRIX-235: SwiftUI keeps a focused value while each new value is equal
/// to it, and the menu item runs the value it kept. So the command holds
/// no value that can change while its title stays the same. It holds the
/// window only, and reads the window's chat when it runs (`target`). Two
/// commands are equal when they have the same title in the same window.
public struct InboxCommand: Equatable {
    /// The chat the command acts on.
    public struct Target: Equatable, Sendable {
        /// The window's selected chat.
        public let selection: ChatSelection
        /// The chat's rooms: one room, or the members of a merged chat.
        public let roomIds: [String]
        /// The chat is archived.
        public let isArchived: Bool

        public init(selection: ChatSelection, roomIds: [String], isArchived: Bool) {
            self.selection = selection
            self.roomIds = roomIds
            self.isArchived = isArchived
        }
    }

    /// The selected chat is archived: the item reads "Unarchive Chat".
    public let isArchived: Bool
    private let windowState: WindowState
    private let target: @MainActor (WindowState) -> Target?
    private let perform: @MainActor (Target, WindowState) -> Void

    /// Nil when the window has no chat to act on.
    ///
    /// - Parameters:
    ///   - windowState: the window.
    ///   - target: the chat the command acts on in a window, or nil. It is
    ///     read now for the title, and again each time the command runs.
    ///   - perform: archives or unarchives a chat in the window.
    @MainActor
    public init?(
        windowState: WindowState,
        target: @escaping @MainActor (WindowState) -> Target?,
        perform: @escaping @MainActor (Target, WindowState) -> Void
    ) {
        guard let current = target(windowState) else { return nil }
        self.isArchived = current.isArchived
        self.windowState = windowState
        self.target = target
        self.perform = perform
    }

    /// Archives or unarchives the chat the window selects now. Does
    /// nothing when the window has no chat to act on.
    @MainActor
    public func toggle() {
        guard let current = target(windowState) else { return }
        perform(current, windowState)
    }

    public static func == (lhs: InboxCommand, rhs: InboxCommand) -> Bool {
        lhs.isArchived == rhs.isArchived && lhs.windowState === rhs.windowState
    }
}
