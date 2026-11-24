import Core
import Models
import SwiftUI

/// The Go menu. "Quick Open…" (⌘K, MATRIX-114) shows the quick switcher in
/// the key window. MATRIX-115 added navigation over what the key window's
/// sidebar shows, and MATRIX-217 set the keys:
/// - ⌘] and ⌘[ open the next and previous chat of the visible chat list
///   (D-7c). That list is the selected rail item's chats, so in a space the
///   walk stays in the space. It is a plain walk down and up the list, not
///   a navigation history. It stops at each end and does not wrap.
/// - ⌘1…⌘9 select the sidebar rail items in rail order, top to bottom: ⌘1
///   is the Inbox, then the spaces, then the labels. Each menu item has the
///   rail item's name.
/// - ⇧⌘] and ⇧⌘[ select the next and previous rail item, as Safari's tab
///   keys do. This walk wraps, as Safari's does.
/// - ⌘U opens the next unread chat of the visible list below the open
///   chat, and wraps to the top (MATRIX-223, Beeper's "Select Next Unread
///   Chat" key). With no other unread chat the item is off. It keeps no
///   history (Patrick, 2026-11-23).
///
/// MATRIX-217 removed ⌘1…⌘9 for the favourites and the first chat-list rows
/// (D-7b), and the rail's own ⌃1…⌃9 (MATRIX-77). The app binds no ⌥-digit
/// or ⌥⌘-digit key: AeroSpace takes ⌥1…⌥9 for its workspaces. ⌘[ and ⌘]
/// are the macOS Back and Forward keys; a later navigation history needs
/// other keys.
///
/// The composer does not take ⌘[ or ⌘]: `ChatTextView.performKeyEquivalent`
/// claims only a send key, and `NSTextView` binds no bracket key, so the
/// event comes to this menu.
///
/// MATRIX-141: the chat walk is over the sidebar's rows, so a merged chat is
/// one step and its member rooms are not steps of their own. An open by
/// these keys moves the focus to the composer (MATRIX-188).
///
/// A key with no rail item has no menu item: a fixed "⌘7" placeholder would
/// show a title for nothing, and the key does nothing either way.
struct GoCommands: Commands {
    /// Whether the key window shows its quick switcher. `nil` when no main
    /// window is focused or no account is signed in, which disables the item.
    @FocusedBinding(\.quickSwitcherPresented) private var quickSwitcherPresented: Bool?
    /// Whether the key window shows its Bookmarks list (MATRIX-208). `nil`
    /// when no main window is focused or no account is signed in.
    @FocusedBinding(\.bookmarksPresented) private var bookmarksPresented: Bool?
    /// The key window's chat and rail navigation, published by
    /// `GoNavigationPublisher`.
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

            // MATRIX-208: ⇧⌘B, Beeper's and Safari's key for bookmarks.
            // Again closes the list.
            Button("Bookmarks") {
                bookmarksPresented?.toggle()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(bookmarksPresented == nil)

            Divider()

            Button("Next Chat") {
                open(navigation?.nextChat)
            }
            .keyboardShortcut("]", modifiers: [.command])
            .disabled(navigation?.nextChat == nil)

            Button("Previous Chat") {
                open(navigation?.previousChat)
            }
            .keyboardShortcut("[", modifiers: [.command])
            .disabled(navigation?.previousChat == nil)

            // MATRIX-223: ⌘U, Beeper's key.
            Button("Next Unread Chat") {
                open(navigation?.nextUnreadChat)
            }
            .keyboardShortcut("u", modifiers: [.command])
            .disabled(navigation?.nextUnreadChat == nil)

            Divider()

            // ⇧⌘] and ⇧⌘[ are bound as the shifted characters "}" and "{".
            // AppKit matches a menu key equivalent against the event's
            // `charactersIgnoringModifiers`, which keeps Shift: ⇧⌘] arrives
            // as "}". SwiftUI passes `"]"` + Shift through unchanged, and an
            // item bound that way never fires on a US layout.
            Button("Next Space or Label") {
                select(navigation?.nextRailItem)
            }
            .keyboardShortcut("}", modifiers: [.command])
            .disabled(navigation?.nextRailItem == nil)

            Button("Previous Space or Label") {
                select(navigation?.previousRailItem)
            }
            .keyboardShortcut("{", modifiers: [.command])
            .disabled(navigation?.previousRailItem == nil)

            let railShortcuts = navigation?.railShortcuts ?? []
            if !railShortcuts.isEmpty {
                Divider()
            }

            ForEach(Array(railShortcuts.enumerated()), id: \.offset) { index, item in
                Button(item.name) {
                    select(item.filter)
                }
                .keyboardShortcut(Self.digitKey(forShortcutAt: index), modifiers: [.command])
            }
        }
    }

    /// Selects a row's chat in the key window, as a click on the row does,
    /// and moves the focus to its composer (MATRIX-188).
    private func open(_ selection: ChatSelection?) {
        guard let selection else { return }
        windowState?.open(selection, from: .shortcut)
    }

    /// Selects a rail item in the key window, as a click on the item does,
    /// and peeks its name next to the rail (MATRIX-227).
    private func select(_ filter: ChatListRailFilter?) {
        guard let filter else { return }
        windowState?.selectRailItemFromGoMenu(filter)
    }

    /// ⌘1 for index 0, up to ⌘9 for index 8.
    private static func digitKey(forShortcutAt index: Int) -> KeyEquivalent {
        KeyEquivalent(Character(String(index + 1)))
    }
}

/// The Go menu's targets in one window (MATRIX-115, MATRIX-217). Only the
/// results are published, not the room list, so the menu rebuilds only when
/// a target changes.
struct GoNavigation: Equatable {
    /// The chat ⌘] opens, or `nil` at the end of the list.
    let nextChat: ChatSelection?
    /// The chat ⌘[ opens, or `nil` at the start or with no selection.
    let previousChat: ChatSelection?
    /// The chat ⌘U opens (MATRIX-223), or `nil` when no other chat of the
    /// list is unread.
    let nextUnreadChat: ChatSelection?
    /// ⌘1…⌘9 in key order: the rail items. Shorter than nine when the rail
    /// has fewer items.
    let railShortcuts: [ChatListRailItem]
    /// The rail item ⇧⌘] selects, or `nil` when the rail has no other item.
    let nextRailItem: ChatListRailFilter?
    /// The rail item ⇧⌘[ selects, or `nil` when the rail has no other item.
    let previousRailItem: ChatListRailFilter?
}

/// Publishes the window's `GoNavigation` for the Go menu.
///
/// A modifier, not part of `MainView.body`, so a room list change
/// re-evaluates only this body and not the whole window. It reads the rooms
/// through `SidebarView.visibleChatList`, the function the sidebar draws, and
/// the rail items by the rules `SidebarLabelRail` draws with.
struct GoNavigationPublisher: ViewModifier {
    @Environment(AppState.self) private var appState
    let windowState: WindowState

    func body(content: Content) -> some View {
        content.focusedSceneValue(\.goNavigation, navigation)
    }

    /// `nil` when no account is signed in, which disables the items.
    private var navigation: GoNavigation? {
        guard let client = appState.matrixClient else { return nil }
        let ordered = SidebarView.visibleChatList(client: client, windowState: windowState).visible.ordered
        let orderedIds = ordered.map(\.id)
        let selectedItemId = windowState.chatSelection?.itemId
        let selectionById = Dictionary(ordered.map { ($0.id, $0.selection) }, uniquingKeysWith: { first, _ in first })
        let labels = client.labels?.document ?? ChatLabelDocument()
        let spaces = SidebarRail.spaceItems(client: client)
        let railItems = ChatListRailNavigation.items(spaces: spaces, labels: labels.labels)
        let railFilters = railItems.map(\.filter)
        // The selected rail item as the rail shows it: a label or a space
        // that is not on the rail selects the Inbox.
        let railSelection = windowState.railFilter.resolved(labels: labels, spaceIds: Set(spaces.map(\.id)))
        return GoNavigation(
            nextChat: ChatListNavigation.next(after: selectedItemId, in: orderedIds).flatMap { selectionById[$0] },
            previousChat: ChatListNavigation.previous(before: selectedItemId, in: orderedIds).flatMap { selectionById[$0] },
            nextUnreadChat: ChatListNavigation.nextUnread(after: selectedItemId, in: ordered),
            railShortcuts: ChatListRailNavigation.shortcutTargets(in: railItems),
            nextRailItem: ChatListRailNavigation.next(after: railSelection, in: railFilters),
            previousRailItem: ChatListRailNavigation.previous(before: railSelection, in: railFilters)
        )
    }
}

extension FocusedValues {
    /// The key window's quick switcher presentation, published by `MainView`.
    @Entry var quickSwitcherPresented: Binding<Bool>?
    /// The key window's Bookmarks list presentation, published by `MainView`
    /// (MATRIX-208).
    @Entry var bookmarksPresented: Binding<Bool>?
    /// The key window's chat and rail navigation, published by
    /// `GoNavigationPublisher`.
    @Entry var goNavigation: GoNavigation?
}
