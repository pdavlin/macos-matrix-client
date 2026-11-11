import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI

struct RoomContextMenu: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) var windowState
    @Environment(\.openWindow) private var openWindow

    let room: SidebarRoom

    var body: some View {
        // MATRIX-116: a single-room window, or the room's open one brought
        // forward.
        Button {
            openWindow(value: RoomWindowID(roomId: room.id))
        } label: {
            Label("Open in New Window", systemImage: "macwindow.badge.plus")
        }

        Divider()

        if let roomInfo = room.roomInfo {
            Button {
                Task {
                    do {
                        Logger.viewCycle.info("marking room unread/read")
                        try await room.room.setUnreadFlag(newValue: !roomInfo.isMarkedUnread)
                    } catch {
                        Logger.viewCycle.error("failed to mark room unread/read: \(error)")
                    }
                }
            } label: {
                if roomInfo.isMarkedUnread {
                    Text("Mark as Read")
                } else {
                    Text("Mark as Unread")
                }
            }

            Button {
                Task {
                    do {
                        Logger.viewCycle.info("mark room favourite: \(!roomInfo.isFavourite)")
                        try await room.room.setIsFavourite(isFavourite: !roomInfo.isFavourite, tagOrder: nil)
                    } catch {
                        Logger.viewCycle.error("failed to mark room favourite: \(error)")
                    }
                }

            } label: {
                if roomInfo.isFavourite {
                    Label("Unfavorite", systemImage: "heart.slash")
                } else {
                    Label("Favorite", systemImage: "heart")
                }
            }

            Button {
                Task {
                    do {
                        Logger.viewCycle.info("mark room low priority: \(!roomInfo.isLowPriority)")
                        try await room.room.setIsLowPriority(isLowPriority: !roomInfo.isLowPriority, tagOrder: nil)
                    } catch {
                        Logger.viewCycle.error("failed to mark room low priority: \(error)")
                    }
                }
            } label: {
                // Beeper's Archive maps here (MATRIX-67): the low-priority tag
                // is the archive-like state the SDK exposes.
                if roomInfo.isLowPriority {
                    Label("Move to Inbox", systemImage: "tray.and.arrow.up")
                } else {
                    Label("Move to Low Priority", systemImage: "tray.and.arrow.down")
                }
            }

            AddToLabelMenu(roomId: room.id)

            mergeButton(isDirect: roomInfo.isDirect)

            Button {
                Task {
                    do {
                        let permalink = try await room.room.matrixToPermalink()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(permalink, forType: .string)
                        Logger.viewCycle.debug("copy room link: \(permalink)")
                    } catch {
                        Logger.viewCycle.error("unable to copy room link: \(error)")
                    }
                }
            } label: {
                Label("Copy Link", systemImage: "link")
            }
            .disabled(roomInfo.isDirect)
        }

        Button {
            Task {
                do {
                    Logger.viewCycle.info("leaving room: \(room.room.id())")
                    try await room.room.leave()
                    // MATRIX-141 (orchestrator decision 2026-11-11): a room
                    // the user leaves here leaves its merged chat. There is
                    // no automatic prune of rooms left elsewhere.
                    appState.matrixClient?.mergedChats?.removeLeftRoom(room.id)
                    try await room.room.forget()

                    if windowState.selectedRoomId == room.room.id() {
                        windowState.selectedRoomId = nil
                    }
                } catch {
                    Logger.viewCycle.error("failed to leave room: \(error)")
                }
            }
        } label: {
            Label("Leave Room", systemImage: "minus.circle")
        }
    }

    /// "Merge with…" (MATRIX-141): opens the Merge Chats sheet with this
    /// chat. Only a one-to-one chat in no merged chat offers it (v1 limit).
    @ViewBuilder
    private func mergeButton(isDirect: Bool) -> some View {
        let mergedChats = appState.matrixClient?.mergedChats
        let document = mergedChats?.document ?? MergedChatDocument()
        if let mergedChats, RoomMergeStatus.of(roomId: room.id, isDirect: isDirect, document: document) == .mergeable {
            Button {
                windowState.mergeEditor = .create(roomId: room.id)
            } label: {
                Label("Merge with…", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(!mergedChats.isEditable)
        }
    }
}
