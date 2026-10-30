import SwiftUI

/// Modifiers that exist on macOS only. Each one applies the AppKit-backed
/// behavior on macOS and the closest iOS equivalent (or nothing) on iOS.
extension View {
    /// `.buttonStyle(.link)` on macOS. iOS has no link style, so it uses
    /// `.borderless`, which also draws a tinted label with no button chrome.
    func linkButtonStyle() -> some View {
        #if os(macOS)
            buttonStyle(.link)
        #else
            buttonStyle(.borderless)
        #endif
    }

    /// `.pickerStyle(.radioGroup)` on macOS. iOS has no radio group, so it
    /// uses `.inline`, which also shows every option at once.
    func radioGroupPickerStyle() -> some View {
        #if os(macOS)
            pickerStyle(.radioGroup)
        #else
            pickerStyle(.inline)
        #endif
    }

    /// `.pointerStyle(.link)` on macOS. iOS has no pointer style API, so the
    /// view is unchanged there.
    func linkPointerStyle() -> some View {
        #if os(macOS)
            pointerStyle(.link)
        #else
            self
        #endif
    }
}
