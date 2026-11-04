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
    case none
}

@MainActor @Observable
public final class WindowState {
    public var selectedScreen: SelectedScreen = .none

    public var selectedRoomId: String?
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

    /// The label selected in the sidebar rail (MATRIX-77), or nil for the
    /// Inbox. Restored per window. An ID the labels do not hold (yet, or any
    /// more) shows the Inbox.
    public var selectedLabelId: String?

    /// The label sheet to show, if any (MATRIX-77). Not restored.
    public var labelEditor: LabelEditorRequest?

    public init() {}

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
    public struct SceneStorageRepresentation: Codable {
        public let selectedRoomId: String?
        public let inspectorVisible: Bool
        public let sidebarSections: SidebarSectionCollapsibility
        /// Optional so a window saved before MATRIX-67, which has no filter,
        /// still decodes; it restores as the inbox.
        public let chatListFilter: ChatListFilter?
        /// MATRIX-77. Optional, so older windows restore with the Inbox.
        public let selectedLabelId: String?

        @MainActor public init(windowState: WindowState) {
            self.selectedRoomId = windowState.selectedRoomId
            self.inspectorVisible = windowState.inspectorVisible
            self.sidebarSections = windowState.sidebarSections
            self.chatListFilter = windowState.chatListFilter
            self.selectedLabelId = windowState.selectedLabelId
        }

        @MainActor public func restore(windowState: WindowState) {
            windowState.selectedRoomId = selectedRoomId
            windowState.inspectorVisible = inspectorVisible
            windowState.sidebarSections = sidebarSections
            windowState.chatListFilter = chatListFilter ?? .inbox
            windowState.selectedLabelId = selectedLabelId
        }
    }

    public convenience init?(rawValue: String) {
        guard
            let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode(SceneStorageRepresentation.self, from: data)
        else {
            Logger.windowState.warning("Failed to recover WindowState from storage: \(rawValue)")
            return nil
        }

        self.init()
        decoded.restore(windowState: self)
        Logger.windowState.info("WindowState recovered from storage: \(rawValue)")
    }

    public var rawValue: String {
        guard
            let data = try? JSONEncoder().encode(SceneStorageRepresentation(windowState: self)),
            let result = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return result
    }

    public typealias RawValue = String
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

public enum SearchToken: Hashable, Identifiable {
    case users, rooms, spaces, messages
    case resolvedRoomAlias(alias: String, resolvedRoom: ResolvedRoomAlias)
    case resolvedRoomId(roomPreview: MatrixRustSDK.RoomPreview)
    case resolvedUser(profile: MatrixRustSDK.UserProfile)

    public var id: Self { self }
}
