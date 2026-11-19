import SwiftUI
import Tokens

/// A timeline with its composer floating over the bottom (MATRIX-198).
///
/// The timeline fills the pane to the bottom edge, and the composer floats
/// over it, so rows scroll under the composer's glass (MATRIX-195), the way
/// they scroll under the toolbar. The composer is the one glass overlay over
/// the timeline (contract §11, 2026-11-18); the other overlays stay opaque.
///
/// The composer's height, plus `gap`, is the timeline's bottom content inset,
/// and it follows every change of that height: more lines of text, the
/// attachments, the reply or edit bar, the thread reply notice. The timeline
/// applies the inset itself (the Mac timeline as its scroll view's bottom
/// content inset), so at the bottom the newest row rests above the composer.
/// The scroll-to-bottom chip sits above the composer too.
///
/// The room chat, the thread panel (a room chat in the inspector), and the
/// merged chat use it.
public struct TimelineComposerLayout<Timeline: View, Composer: View>: View {
    /// Whether the timeline shows its newest end. The chip shows when not.
    let isAtBottom: Bool
    /// The messages that arrived below the viewport, for the chip.
    let unseenCount: Int
    /// What the chip does.
    let scrollToBottom: () -> Void
    /// The timeline, made with the bottom inset it must apply.
    let timeline: (_ bottomInset: CGFloat) -> Timeline
    /// The composer stack. Its height is measured.
    let composer: Composer

    /// The composer's measured height. 0 while there is no composer.
    @State private var composerHeight: CGFloat = 0

    /// The space between the newest row and the top of the composer.
    public static var gap: CGFloat {
        8
    }

    /// - Parameters:
    ///   - isAtBottom: Whether the timeline shows its newest end.
    ///   - unseenCount: The messages that arrived below the viewport.
    ///   - scrollToBottom: What the scroll-to-bottom chip does.
    ///   - timeline: The timeline, made with the bottom inset it must apply.
    ///   - composer: The composer stack, without a background of its own
    ///     across the pane.
    public init(
        isAtBottom: Bool,
        unseenCount: Int,
        scrollToBottom: @escaping () -> Void,
        timeline: @escaping (_ bottomInset: CGFloat) -> Timeline,
        @ViewBuilder composer: () -> Composer
    ) {
        self.isAtBottom = isAtBottom
        self.unseenCount = unseenCount
        self.scrollToBottom = scrollToBottom
        self.timeline = timeline
        self.composer = composer()
    }

    /// The timeline's bottom content inset: the composer and the gap, or 0
    /// with no composer.
    public static func bottomInset(composerHeight: CGFloat) -> CGFloat {
        composerHeight > 0 ? composerHeight + gap : 0
    }

    public var body: some View {
        let bottomInset = Self.bottomInset(composerHeight: composerHeight)
        timeline(bottomInset)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .bottomTrailing) {
                if !isAtBottom {
                    ScrollToBottomChip(unseenCount: unseenCount, action: scrollToBottom)
                        .padding(.trailing, DensityToken.scrollChipMargin)
                        .padding(.bottom, bottomInset + DensityToken.scrollChipMargin)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                composer
                    // Its own height, not the pane's: the overlay offers the
                    // whole pane.
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        composerHeight = height
                    }
            }
    }
}
