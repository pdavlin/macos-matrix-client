import Core
import Models
import SwiftUI
import Tokens

struct AppCommands: Commands {
    @FocusedValue(WindowState.self) private var windowState: WindowState?
    @Environment(\.openWindow) private var openWindow
    /// The key window's broadcast (MATRIX-168), or nil when it has none.
    @FocusedValue(\.broadcastCommand) private var broadcastCommand: BroadcastCommand?
    /// The key window's Archive command (MATRIX-206), or nil when no chat is
    /// selected.
    @FocusedValue(\.inboxCommand) private var inboxCommand: InboxCommand?
    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize

    /// The key window's state when it is a main window. A single-room
    /// window (MATRIX-116) shows one room only, so New Chat and New Group
    /// are disabled there.
    private var mainWindowState: WindowState? {
        windowState?.isSingleRoomWindow == true ? nil : windowState
    }

    var body: some Commands {
        SidebarCommands()
        InspectorCommands()
        TextEditingCommands()
        ToolbarCommands()

        newItems
        newTab
        fontSizeCommands
    }

    /// File > New (MATRIX-75): ⌘N is New Chat and ⇧⌘N is New Group, as in
    /// Beeper. Replacing `.newItem` drops the WindowGroup's default ⌘N
    /// "New Window", which moves to ⌥⌘N. The full create-room form stays
    /// reachable without a shortcut.
    var newItems: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                mainWindowState?.selectedScreen = .newChat(mode: .direct)
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(mainWindowState == nil)

            Button("New Group") {
                mainWindowState?.selectedScreen = .newChat(mode: .group)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(mainWindowState == nil)

            Button("New Room with Options…") {
                mainWindowState?.selectedScreen = .newRoom
            }
            .disabled(mainWindowState == nil)

            Divider()

            Button("New Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
    }

    var newTab: some Commands {
        CommandGroup(after: .newItem) {
            Button(action: {
                guard let currentMainWindow = NSApp.orderedWindows.first(where: { window in
                    window.identifier?.rawValue.starts(with: "main-AppWindow") ?? false
                }) else {
                    return
                }

                guard let windowController = currentMainWindow.windowController else {
                    return
                }

                windowController.newWindowForTab(nil)
                if let newWindow = NSApp.keyWindow, currentMainWindow != newWindow {
                    currentMainWindow.addTabbedWindow(newWindow, ordered: .above)
                    newWindow.makeKeyAndOrderFront(nil)
                }
            }) {
                Text("New Tab")
            }
            .keyboardShortcut("t", modifiers: [.command])

            Divider()

            // MATRIX-168: enabled while the key window's rail filter is a
            // label or a space that shows a chat. No shortcut: the sheet
            // sends to many chats.
            Button(broadcastCommand.map { "Broadcast to \($0.filterName)…" } ?? "Broadcast…") {
                broadcastCommand?.open()
            }
            .disabled(broadcastCommand == nil)

            Divider()

            // MATRIX-206: ⌘E, as in Beeper. In the File menu because AppKit
            // matches key equivalents in menu order and the Edit menu's
            // "Use Selection for Find" also takes ⌘E.
            Button(inboxCommand?.isArchived == true ? "Unarchive Chat" : "Archive Chat") {
                inboxCommand?.toggle()
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(inboxCommand == nil)
        }
    }

    /// The sidebar toolbar's compose button, which opens New Chat
    /// (MATRIX-75). It keeps its pre-MATRIX-75 name because `SidebarView`
    /// calls it and MATRIX-67 is rewriting that file; rename it once that
    /// lands. The shortcut belongs to the File menu item, not this button.
    static func createRoomButton(windowState: WindowState) -> some View {
        Button {
            windowState.selectedScreen = .newChat(mode: .direct)
        } label: {
            Label("New Chat", systemImage: "square.and.pencil")
        }
        .help("Start a new chat (⌘N)")
    }

    var fontSizeCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button {
                fontSize += 1
            } label: {
                Text("Make Text Bigger")
            }
            .keyboardShortcut("+", modifiers: [.command])
            .disabled(fontSize >= TypographyToken.maxBaseFontSize)

            Button {
                fontSize = TypographyToken.defaultBaseFontSize
            } label: {
                Text("Make Text Normal Size")
            }
            .keyboardShortcut("0", modifiers: [.command])
            .disabled(fontSize == TypographyToken.defaultBaseFontSize)

            Button {
                fontSize -= 1

            } label: {
                Text("Make Text Smaller")
            }
            .keyboardShortcut("-", modifiers: [.command])
            .disabled(fontSize <= TypographyToken.minBaseFontSize)
        }
    }
}
