import Core
import Models
import SwiftUI

/// The Go menu. "Quick Open…" (⌘K, MATRIX-114) shows the quick switcher in
/// the key window. MATRIX-115 adds room navigation over what the key
/// window's sidebar shows:
/// - ⇧⌘] and ⇧⌘[ open the next and previous room (D-7c).
/// - ⌘1…⌘9 open the favourites in grid order, then the first chat-list
///   rows (D-7b).
///
/// A key with no room has no item: a fixed "⌘7" placeholder would show a
/// title for nothing, and the key does nothing either way. With fewer than
/// nine visible rooms the list is short anyway (a narrow filter or label).
struct GoCommands: Commands {
    /// Whether the key window shows its quick switcher. `nil` when no main
    /// window is focused or no account is signed in, which disables the item.
    @FocusedBinding(\.quickSwitcherPresented) private var quickSwitcherPresented: Bool?
    /// The key window's room navigation, published by `GoNavigationPublisher`.
    @FocusedValue(\.goNavigation) private var navigation: GoNavigation?
    @FocusedValue(WindowState.self) private var windowState: WindowState?

    var body: some Commands {
        CommandMenu("Go") {
            Button("Quick Open…") {
                // ⌘K again closes the switcher.
                quickSwitcherPresented?.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(quickSwitcherPresented == nil)

            Divider()

            // ⇧⌘] and ⇧⌘[ are bound as the shifted characters "}" and "{".
            // AppKit matches a menu key equivalent against the event's
            // `charactersIgnoringModifiers`, which keeps Shift: ⇧⌘] arrives
            // as "}". SwiftUI passes `"]"` + Shift through unchanged, and an
            // item bound that way never fires on a US layout.
            Button("Next Chat") {
                open(navigation?.nextRoomId)
            }
            .keyboardShortcut("}", modifiers: [.command])
            .disabled(navigation?.nextRoomId == nil)

            Button("Previous Chat") {
                open(navigation?.previousRoomId)
            }
            .keyboardShortcut("{", modifiers: [.command])
            .disabled(navigation?.previousRoomId == nil)

            let shortcutRooms = navigation?.shortcutRooms ?? []
            if !shortcutRooms.isEmpty {
                Divider()
            }

            ForEach(Array(shortcutRooms.enumerated()), id: \.offset) { index, room in
                Button(room.name) {
                    open(room.id)
                }
                .keyboardShortcut(Self.digitKey(forShortcutAt: index), modifiers: [.command])
            }
        }
    }

    /// Selects `roomId` in the key window, as a click on its sidebar row does.
    private func open(_ roomId: String?) {
        guard let roomId else { return }
        windowState?.selectedRoomId = roomId
    }

    /// ⌘1 for index 0, up to ⌘9 for index 8.
    private static func digitKey(forShortcutAt index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}

/// A room a ⌘-digit item opens.
struct GoShortcutRoom: Equatable {
    let id: String
    /// The room's display name, as the sidebar shows it. The item title.
    let name: String
}

/// The Go menu's targets in one window (MATRIX-115). Only the results are
/// published, not the room list, so the menu rebuilds only when a target
/// changes.
struct GoNavigation: Equatable {
    /// ⌘1…⌘9 in key order. Shorter than nine when fewer rooms show.
    let shortcutRooms: [GoShortcutRoom]
    /// The room ⇧⌘] opens, or `nil` at the end of the list.
    let nextRoomId: String?
    /// The room ⇧⌘[ opens, or `nil` at the start or with no selection.
    let previousRoomId: String?
}

/// Publishes the window's `GoNavigation` for the Go menu.
///
/// A modifier, not part of `MainView.body`, so a room list change
/// re-evaluates only this body and not the whole window. It reads the rooms
/// through `SidebarView.visibleChatList`, the function the sidebar draws.
struct GoNavigationPublisher: ViewModifier {
    @Environment(AppState.self) private var appState
    let windowState: WindowState

    func body(content: Content) -> some View {
        content.focusedSceneValue(\.goNavigation, navigation)
    }

    /// `nil` when no account is signed in, which disables the items.
    private var navigation: GoNavigation? {
        guard let client = appState.matrixClient else { return nil }
        let ordered = SidebarView.visibleChatList(client: client, windowState: windowState).ordered
        let orderedIds = ordered.map(\.id)
        let selectedRoomId = windowState.selectedRoomId
        return GoNavigation(
            shortcutRooms: ChatListNavigation.shortcutTargets(in: ordered).map { room in
                // The row's own title, so the item reads as the sidebar does.
                GoShortcutRoom(id: room.id, name: room.chatListRow().title)
            },
            nextRoomId: ChatListNavigation.next(after: selectedRoomId, in: orderedIds),
            previousRoomId: ChatListNavigation.previous(before: selectedRoomId, in: orderedIds)
        )
    }
}

extension FocusedValues {
    /// The key window's quick switcher presentation, published by `MainView`.
    @Entry var quickSwitcherPresented: Binding<Bool>?
    /// The key window's room navigation, published by `GoNavigationPublisher`.
    @Entry var goNavigation: GoNavigation?
}
