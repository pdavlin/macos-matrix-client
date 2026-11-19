import SwiftUI

/// The system scroll edge effect where content scrolls under the toolbar
/// (MATRIX-196). The effect belongs to the chrome: the rows stay opaque, and
/// no view draws a fade or blur of its own.
///
/// The SwiftUI scroll views of the sidebar (the chat list and the label rail)
/// set this style. The timeline is an AppKit `NSScrollView`: AppKit gives it
/// the same effect (its scroll pocket) because it runs under the toolbar, and
/// the macOS 26 SDK has no public API to set the style of a plain
/// `NSScrollView`. `NSScrollEdgeEffectStyle` goes only to titlebar and split
/// view item accessories, which the app does not use. So the timeline keeps
/// the automatic style.
public enum ScrollEdgeToken {
    /// The style of the effect at the top edge of a sidebar scroll view.
    public static let sidebarTop: ScrollEdgeEffectStyle = .soft
}
