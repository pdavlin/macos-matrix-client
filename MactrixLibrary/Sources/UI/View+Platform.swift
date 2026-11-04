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

    /// `.frame(width:)` on macOS, where a sheet sizes to its content. An iOS
    /// sheet is as wide as the screen, so a fixed width wider than an iPhone
    /// clips the content. iOS uses the width as a maximum instead.
    func sheetContentWidth(_ width: CGFloat) -> some View {
        #if os(macOS)
            frame(width: width)
        #else
            frame(maxWidth: width)
        #endif
    }

    /// Turns off auto-capitalization and autocorrection on iOS. Both change
    /// the characters of a typed key, which then fails to match. macOS is
    /// unchanged.
    func keyEntryTextTraits() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        #else
            self
        #endif
    }
}
