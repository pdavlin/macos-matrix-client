import Foundation

/// The part of a main window's state that is kept between launches: the
/// selected chat, the inspector, the sidebar sections, the list filter and
/// the rail selection.
///
/// One JSON object. Two places hold it: the window's `SceneStorage` value,
/// and `WindowStateStore` (MATRIX-175). The keys are the same as before
/// MATRIX-175, when the type was `WindowState.SceneStorageRepresentation`,
/// so an old stored value still decodes. Each field that came after the
/// first version is optional, so a value stored without it decodes.
///
/// The snapshot holds IDs as they were saved. It does not check them: a
/// space or a label that is not known shows the Inbox by
/// `ChatListRailFilter.resolved(labels:spaceIds:)`, and applies when it
/// arrives.
public struct WindowStateSnapshot: Codable, Equatable, Sendable {
    public var selectedRoomId: String?
    /// MATRIX-141. Optional, so older windows restore their room.
    public var selectedMergedChatId: String?
    public var inspectorVisible: Bool
    public var sidebarSections: SidebarSectionCollapsibility
    /// Optional so a window saved before MATRIX-67, which has no filter,
    /// still decodes; it restores as the inbox.
    public var chatListFilter: ChatListFilter?
    /// MATRIX-77. Optional, so older windows restore with the Inbox.
    public var selectedLabelId: String?
    /// MATRIX-167. Optional, so older windows restore their label or
    /// the Inbox.
    public var selectedSpaceId: String?

    public init(
        chatSelection: ChatSelection? = nil,
        inspectorVisible: Bool = false,
        sidebarSections: SidebarSectionCollapsibility = SidebarSectionCollapsibility(),
        chatListFilter: ChatListFilter = .inbox,
        railFilter: ChatListRailFilter = .inbox
    ) {
        selectedRoomId = chatSelection?.roomId
        selectedMergedChatId = chatSelection?.mergedChatId
        self.inspectorVisible = inspectorVisible
        self.sidebarSections = sidebarSections
        self.chatListFilter = chatListFilter
        selectedLabelId = railFilter.labelId
        selectedSpaceId = railFilter.spaceId
    }

    /// The saved selection: the merged chat, else the room, else nothing.
    public var chatSelection: ChatSelection? {
        selectedMergedChatId.map(ChatSelection.merged) ?? selectedRoomId.map(ChatSelection.room)
    }

    /// The saved list filter. A value with no filter gives the inbox.
    public var restoredChatListFilter: ChatListFilter {
        chatListFilter ?? .inbox
    }

    /// The saved rail selection: the space, else the label, else the Inbox.
    public var railFilter: ChatListRailFilter {
        selectedSpaceId.map(ChatListRailFilter.space)
            ?? selectedLabelId.map(ChatListRailFilter.label)
            ?? .inbox
    }

    /// The snapshot in a stored JSON string, or nil when the string does not
    /// decode.
    public init?(json: String) {
        guard let decoded = try? JSONDecoder().decode(WindowStateSnapshot.self, from: Data(json.utf8)) else {
            return nil
        }
        self = decoded
    }

    /// The JSON string to store. The keys are sorted, so equal snapshots
    /// give equal strings.
    public var json: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// The last state of a main window, in the app's own defaults (MATRIX-175).
///
/// `SceneStorage` depends on macOS window restoration. With the system
/// setting "Close windows when quitting an application" on (the default),
/// macOS discards that state at quit. This store does not depend on it.
///
/// One JSON string under one key. The key is app-wide, the same as the other
/// defaults of the app (the sidebar width, the room window size): the app
/// has one account. With more than one main window, the last state written
/// is the stored state.
public struct WindowStateStore {
    /// The `UserDefaults` key.
    public static let storageKey = "MainWindow.lastState"

    private let defaults: UserDefaults

    /// - Parameter defaults: the store. Tests pass an isolated suite.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored state, or nil when there is none or it does not decode.
    public func load() -> WindowStateSnapshot? {
        defaults.string(forKey: Self.storageKey).flatMap(WindowStateSnapshot.init(json:))
    }

    /// Stores `snapshot`. A snapshot equal to the stored value writes
    /// nothing.
    public func save(_ snapshot: WindowStateSnapshot) {
        guard let json = snapshot.json, json != defaults.string(forKey: Self.storageKey) else { return }
        defaults.set(json, forKey: Self.storageKey)
    }
}

/// Where a new main window gets its first state (MATRIX-175).
public enum WindowRestoreSource: Equatable, Sendable {
    /// macOS restored the window: its `SceneStorage` value applies.
    case sceneStorage
    /// The state in `WindowStateStore` applies.
    case savedState
    /// The window starts empty.
    case none
}

/// The rule for which main window starts from the saved state (MATRIX-175).
///
/// - A window that macOS restored keeps its own `SceneStorage` state.
/// - The first main window of a launch, when it has no `SceneStorage`
///   value, starts from the saved state.
/// - A later window with no `SceneStorage` value (File > New Window) starts
///   empty: it does not copy the selection of the first.
///
/// The first window uses up the launch's one restore, restored by macOS or
/// not. One value lives for the whole app session.
public struct LaunchWindowRestore: Equatable, Sendable {
    /// Whether a main window opened in this launch.
    public private(set) var firstWindowOpened = false

    public init() {}

    /// Takes a new main window.
    ///
    /// - Parameter hasSceneStorageValue: whether the window's state came
    ///   from its `SceneStorage` value.
    /// - Returns: the source of the window's first state.
    public mutating func source(hasSceneStorageValue: Bool) -> WindowRestoreSource {
        let isFirst = !firstWindowOpened
        firstWindowOpened = true
        if hasSceneStorageValue {
            return .sceneStorage
        }
        return isFirst ? .savedState : .none
    }
}
