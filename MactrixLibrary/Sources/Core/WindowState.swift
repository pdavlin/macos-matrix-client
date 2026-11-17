import Foundation
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Utils

public enum InspectorContent: Equatable {
    case roomInfo
    case search
    case userInfo(userId: String)
    case roomThreads
    case roomPins
    case focusThread(threadTimeline: LiveTimeline)
}

public enum SearchDirectResult {
    case lookingForRoom(alias: String), roomNotFound(alias: String)
    case resolvedRoomAlias(alias: String, resolvedRoom: MatrixRustSDK.ResolvedRoomAlias)
    case resolvedRoomId(roomPreview: MatrixRustSDK.RoomPreview)
    case lookingForUser(userId: String), userNotFound(userId: String)
    case resolvedUser(profile: MatrixRustSDK.UserProfile)
}

public enum SelectedScreen {
    case joinedRoom(timeline: LiveTimeline)
    case loadMatrixUrl(_ url: Utils.MatrixUriScheme)
    case previewRoom(_ room: MatrixRustSDK.RoomPreview)
    case user(profile: MatrixRustSDK.UserProfile)
    case newRoom
    /// The Beeper-style new chat draft in the detail pane (MATRIX-75).
    case newChat(mode: NewChatMode)
    /// A merged chat (MATRIX-141), by its ID. Phase B shows a placeholder;
    /// the merged timeline replaces it.
    case mergedChat(id: String)
    case none
}

@MainActor @Observable
public final class WindowState {
    public var selectedScreen: SelectedScreen = .none

    /// What the window selects: a room or a merged chat (MATRIX-141). The
    /// one stored value, so a room and a merged chat are never selected at
    /// once. `selectedRoomId` and `selectedMergedChatId` read and write it.
    ///
    /// In a main window, a member room never stays selected: `MainView` moves
    /// the selection to the room's merged chat
    /// (`MergedChatSelection.resolve`).
    public var chatSelection: ChatSelection?

    /// The selected room, or nil when no room or a merged chat is selected.
    /// Setting a room ID replaces any selection. Setting nil clears a
    /// selected room and leaves a selected merged chat alone.
    public var selectedRoomId: String? {
        get { chatSelection?.roomId }
        set {
            if let newValue {
                chatSelection = .room(newValue)
            } else if chatSelection?.roomId != nil {
                chatSelection = nil
            }
        }
    }

    /// The selected merged chat's ID (MATRIX-141), or nil. Setting an ID
    /// replaces any selection. Setting nil clears a selected merged chat and
    /// leaves a selected room alone.
    public var selectedMergedChatId: String? {
        get { chatSelection?.mergedChatId }
        set {
            if let newValue {
                chatSelection = .merged(newValue)
            } else if chatSelection?.mergedChatId != nil {
                chatSelection = nil
            }
        }
    }

    public var inspectorVisible: Bool = false

    public var inspectorContent: InspectorContent = .roomInfo

    public var requestedVerification = false

    public var searchQuery: String = ""
    public var searchTokens: [SearchToken] = []
    public var searchDirectResult: SearchDirectResult?

    /// The collapsed/expanded states of the sections in the sidebar.
    public var sidebarSections = SidebarSectionCollapsibility()

    /// The sidebar chat-list filter (MATRIX-67). Restored per window.
    public var chatListFilter: ChatListFilter = .inbox

    /// The sidebar rail's selection (MATRIX-167): the Inbox, one space, or
    /// one label. Restored per window. A label the labels do not hold, or a
    /// space that is not on the rail (yet, or any more), shows the Inbox:
    /// see `ChatListRailFilter.resolved(labels:spaceIds:)`.
    public var railFilter: ChatListRailFilter = .inbox

    /// The label selected in the sidebar rail (MATRIX-77), or nil when the
    /// rail selects the Inbox or a space. A view of `railFilter`.
    public var selectedLabelId: String? {
        get { railFilter.labelId }
        set { railFilter = newValue.map(ChatListRailFilter.label) ?? .inbox }
    }

    /// The space whose rooms the "Browse Rooms" sheet shows, if any
    /// (MATRIX-167). Not restored.
    public var spaceBrowser: SpaceBrowserRequest?

    /// The label sheet to show, if any (MATRIX-77). Not restored.
    public var labelEditor: LabelEditorRequest?

    /// The broadcast sheet to show, if any (MATRIX-168). Not restored.
    public var broadcast: BroadcastRequest?

    /// The Merge Chats sheet to show, if any (MATRIX-141). Not restored.
    public var mergeEditor: MergedChatEditorRequest?

    /// The one room a single-room window shows (MATRIX-116), or `nil` for a
    /// main window. A single-room window never shows another room, so the
    /// menu commands that change the selection skip it.
    public let singleRoomId: String?

    /// Whether the state came from the window's `SceneStorage` value: macOS
    /// restored the window (MATRIX-175).
    @ObservationIgnored public private(set) var recoveredFromSceneStorage = false

    /// Whether this is a single-room window (MATRIX-116).
    public var isSingleRoomWindow: Bool {
        singleRoomId != nil
    }

    /// - Parameter singleRoomId: the room of a single-room window, or `nil`
    ///   (the default) for a main window.
    public init(singleRoomId: String? = nil) {
        self.singleRoomId = singleRoomId
        self.chatSelection = singleRoomId.map(ChatSelection.room)
    }

    public var searchFocused: Binding<Bool> {
        Binding(
            get: { self.inspectorContent == .search },
            set: { setFocused in
                if setFocused {
                    self.inspectorContent = .search
                    self.inspectorVisible = true
                }

                if !setFocused, self.inspectorContent == .search {
                    self.inspectorContent = .roomInfo
                }
            }
        )
    }

    public func toggleInspector() {
        if inspectorVisible {
            if inspectorContent == .roomInfo {
                inspectorVisible = false
            } else {
                inspectorContent = .roomInfo
            }
        } else {
            inspectorVisible = true
            inspectorContent = .roomInfo
        }
    }

    public func focusMessage(eventId: String) {
        guard case let .joinedRoom(timeline: roomTimeline) = selectedScreen else {
            Logger.windowState.warning("focus message failed, no active timeline")
            return
        }

        /* guard let focusItem = roomTimeline.timelineItems?.first(where: { $0.asEvent()?.eventOrTransactionId.id == eventId }) else {
             Logger.windowState.warning("focus message failed, message not found")
             return
         } */

        Logger.windowState.warning("scrolling to message \(eventId)")
        withAnimation {
            roomTimeline.scrollPosition.scrollTo(id: eventId)
        }
    }

    public func focusThread(rootEventId: String) {
        guard case let .joinedRoom(timeline: roomTimeline) = selectedScreen else { return }

        inspectorVisible = true
        // The panel already holds this thread: keep its timeline, which is
        // loaded and gets each new reply (MATRIX-169).
        if case let .focusThread(threadTimeline: shown) = inspectorContent {
            guard shown.room.id != roomTimeline.room.id || shown.focusedThreadId != rootEventId else { return }
        }
        inspectorContent = .focusThread(threadTimeline: LiveTimeline(room: roomTimeline.room, focusThread: rootEventId))
    }

    public func showRoomThreads() {
        if inspectorVisible, inspectorContent == .roomThreads {
            inspectorVisible = false
        } else {
            inspectorContent = .roomThreads
            inspectorVisible = true
        }
    }

    public func showRoomPins() {
        if inspectorVisible, inspectorContent == .roomPins {
            inspectorVisible = false
        } else {
            inspectorContent = .roomPins
            inspectorVisible = true
        }
    }

    public func focusUser(userId: String) {
        if inspectorVisible, inspectorContent == .userInfo(userId: userId) {
            inspectorVisible = false
        } else {
            inspectorContent = .userInfo(userId: userId)
            inspectorVisible = true
        }
    }
}

extension WindowState: @MainActor RawRepresentable {
    /// The state that is kept between launches (MATRIX-175). The window's
    /// `SceneStorage` value and `WindowStateStore` both hold it.
    public var snapshot: WindowStateSnapshot {
        WindowStateSnapshot(
            chatSelection: chatSelection,
            inspectorVisible: inspectorVisible,
            sidebarSections: sidebarSections,
            chatListFilter: chatListFilter,
            railFilter: railFilter
        )
    }

    /// Puts a saved state in the window. The IDs are not checked here: see
    /// `WindowStateSnapshot`.
    public func restore(_ snapshot: WindowStateSnapshot) {
        chatSelection = snapshot.chatSelection
        inspectorVisible = snapshot.inspectorVisible
        sidebarSections = snapshot.sidebarSections
        chatListFilter = snapshot.restoredChatListFilter
        railFilter = snapshot.railFilter
    }

    public convenience init?(rawValue: String) {
        guard let decoded = WindowStateSnapshot(json: rawValue) else {
            Logger.windowState.warning("Failed to recover WindowState from storage: \(rawValue)")
            return nil
        }

        self.init()
        restore(decoded)
        recoveredFromSceneStorage = true
        Logger.windowState.info("WindowState recovered from storage: \(rawValue)")
    }

    public var rawValue: String {
        snapshot.json ?? ""
    }

    public typealias RawValue = String
}

/// A request to open the broadcast sheet (MATRIX-168): the filter's name
/// and its targets, read when the sheet opens.
public struct BroadcastRequest: Identifiable, Equatable {
    public let id: UUID
    /// The label's or the space's name.
    public let filterName: String
    /// Every chat of the filter that the account has (MATRIX-172): the
    /// sidebar's chats in sidebar order, then the others. Never empty.
    public let targets: [BroadcastTarget]
    /// What is known to be missing from `targets`, or nil for a complete
    /// list (MATRIX-172).
    public let gap: BroadcastTargetGap?

    public init(id: UUID = UUID(), filterName: String, targets: [BroadcastTarget], gap: BroadcastTargetGap? = nil) {
        self.id = id
        self.filterName = filterName
        self.targets = targets
        self.gap = gap
    }
}

/// A request to open the label sheet (MATRIX-77).
public enum LabelEditorRequest: Identifiable, Equatable {
    /// Create a label, with `roomId` checked when the sheet opens from a
    /// chat's context menu.
    case create(preselectedRoomId: String?)
    case edit(labelId: String)

    public var id: String {
        switch self {
        case let .create(roomId): "create:\(roomId ?? "")"
        case let .edit(labelId): "edit:\(labelId)"
        }
    }
}

/// A request to show the rooms of one space (MATRIX-167).
public struct SpaceBrowserRequest: Identifiable, Equatable {
    /// The space's room ID.
    public let spaceId: String

    public init(spaceId: String) {
        self.spaceId = spaceId
    }

    public var id: String { spaceId }
}

public enum SearchToken: Hashable, Identifiable {
    case users, rooms, spaces, messages
    case resolvedRoomAlias(alias: String, resolvedRoom: ResolvedRoomAlias)
    case resolvedRoomId(roomPreview: MatrixRustSDK.RoomPreview)
    case resolvedUser(profile: MatrixRustSDK.UserProfile)

    public var id: Self { self }
}
