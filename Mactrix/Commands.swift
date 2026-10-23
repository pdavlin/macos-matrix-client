import Models
import SwiftUI
import Tokens

struct AppCommands: Commands {
    @FocusedValue(WindowState.self) private var windowState: WindowState?
    @Environment(\.openWindow) private var openWindow
    @AppStorage(TypographyToken.fontSizeStorageKey) var fontSize = TypographyToken.defaultBaseFontSize

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
                windowState?.selectedScreen = .newChat(mode: .direct)
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(windowState == nil)

            Button("New Group") {
                windowState?.selectedScreen = .newChat(mode: .group)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(windowState == nil)

            Button("New Room with Options…") {
                windowState?.selectedScreen = .newRoom
            }
            .disabled(windowState == nil)

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
