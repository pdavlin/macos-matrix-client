import SwiftUI

/// The Go menu (MATRIX-114). "Quick Open…" (⌘K) shows the quick switcher
/// in the key window. MATRIX-115 adds ⌘1…⌘9 and room cycling here
/// (D-7b, D-7c).
struct GoCommands: Commands {
    /// Whether the key window shows its quick switcher. `nil` when no main
    /// window is focused or no account is signed in, which disables the item.
    @FocusedBinding(\.quickSwitcherPresented) private var quickSwitcherPresented: Bool?

    var body: some Commands {
        CommandMenu("Go") {
            Button("Quick Open…") {
                // ⌘K again closes the switcher.
                quickSwitcherPresented?.toggle()
            }
            .keyboardShortcut("k", modifiers: [.command])
            .disabled(quickSwitcherPresented == nil)
        }
    }
}

extension FocusedValues {
    /// The key window's quick switcher presentation, published by `MainView`.
    @Entry var quickSwitcherPresented: Binding<Bool>?
}
