import Models
import SwiftUI
import Tokens

/// One button of the hover action bar.
struct HoverButton<Icon: View>: View {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    let icon: () -> Icon
    let tooltip: LocalizedStringKey
    /// True for a quick-reaction emoji (MATRIX-135): it rests monochrome and
    /// dimmed, and cross-fades to full color while the pointer is over it.
    var restsMonochrome: Bool = false
    let action: () -> Void

    let size: CGFloat = DensityToken.hoverActionButtonSize

    /// The icon is at rest when it is a quick reaction and not under the
    /// pointer.
    private var isResting: Bool {
        restsMonochrome && !hovering
    }

    var body: some View {
        Button(action: action) {
            icon()
                .saturation(isResting ? ReactionToken.quickReactionRestingSaturation : 1)
                .opacity(isResting ? ReactionToken.quickReactionRestingOpacity : 1)
                .animation(
                    MotionToken.animation(MotionToken.standard(duration: MotionToken.hoverDuration), reduceMotion: reduceMotion),
                    value: isResting
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .foregroundStyle(hovering ? Color.accentColor : .primary)
        .background(
            RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                .fill(Color.accentColor.quaternary)
                .frame(width: size, height: size)
                .opacity(hovering ? 1 : 0)
        )
        .frame(width: size, height: size)
        .padding(DensityToken.hoverActionButtonPadding)
        .onHover { hover in
            hovering = hover
        }
    }
}

/// The hover action bar at rest, without its reveal motion: the quick
/// reactions, a divider, then the other actions, on an opaque rounded
/// background with a hairline border and a soft shadow.
///
/// `HoverActionBar` wraps it in the reveal motion. The snapshot tests draw
/// this view, the end state of the reveal.
struct HoverActionBarContent: View {
    let items: [MessageActionItem]
    let perform: @MainActor (MessageAction) -> Void

    private func button(for item: MessageActionItem) -> some View {
        HoverButton(
            icon: {
                if let systemImage = MessageActionPresentation.systemImage(of: item.action) {
                    Image(systemName: systemImage)
                } else {
                    Text(MessageActionPresentation.title(of: item.action))
                }
            },
            tooltip: MessageActionPresentation.hoverTooltip(of: item.action),
            restsMonochrome: item.action.isQuickReaction,
            action: { perform(item.action) }
        )
    }

    var body: some View {
        let reactions = items.filter(\.action.isQuickReaction)
        let others = items.filter { !$0.action.isQuickReaction }

        HStack(spacing: 0) {
            ForEach(reactions) { item in
                button(for: item)
            }
            if !reactions.isEmpty, !others.isEmpty {
                Divider().frame(height: DensityToken.hoverActionsDividerHeight)
            }
            ForEach(others) { item in
                button(for: item)
            }
        }
        // The bar keeps one button's height even when it has no buttons.
        .frame(minHeight: HoverActionBarGeometry.buttonWidth)
        .padding(DensityToken.hoverActionsPadding)
        .background(
            RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                .fill(Color(PlatformColor.controlBackgroundColor))
                .stroke(Color(PlatformColor.separatorColor), lineWidth: BubbleToken.hoverBorderWidth)
                .shadow(color: .black.opacity(BubbleToken.hoverShadowOpacity), radius: BubbleToken.hoverShadowRadius)
        )
    }
}

/// The hover action bar of a message (MATRIX-108, MATRIX-135, MATRIX-145).
///
/// The buttons come from the shared action model:
/// `MessageActionModel.items(for:on: .hoverRow, quickReactionKeys:)`. The
/// quick reactions rest monochrome and take their color under the pointer.
/// The bar fades and slides into place when `isRevealed` becomes true, and
/// fades out when it becomes false (`HoverRevealModifier`). A bar without
/// items does not show.
///
/// The Mac timeline draws one bar above all its rows, in a hosting view the
/// timeline controller owns and places at the hovered row (MATRIX-145).
/// Before MATRIX-145 each row drew its own bar, and the bar hung over the
/// row above, where that row could cover it.
///
/// Usage:
/// ```swift
/// HoverActionBar(
///     items: target.items(on: .hoverRow),
///     isRevealed: true,
///     perform: target.perform
/// )
/// ```
public struct HoverActionBar: View {
    let items: [MessageActionItem]
    let isRevealed: Bool
    let perform: @MainActor (MessageAction) -> Void

    /// - Parameters:
    ///   - items: The hover row items in display order.
    ///   - isRevealed: Whether the bar shows. A change animates.
    ///   - perform: Runs the action of a clicked button.
    public init(
        items: [MessageActionItem],
        isRevealed: Bool,
        perform: @escaping @MainActor (MessageAction) -> Void
    ) {
        self.items = items
        self.isRevealed = isRevealed
        self.perform = perform
    }

    public var body: some View {
        HoverActionBarContent(items: items, perform: perform)
            // MATRIX-135: fade and slide in, fade out.
            .hoverReveal(isRevealed && !items.isEmpty)
    }
}

#Preview {
    let subject = MessageActionSubject(
        content: .text,
        isOwn: true,
        eventId: "$event",
        canBeRepliedTo: true,
        isPinned: false,
        copyableText: "Hello"
    )
    VStack(alignment: .trailing, spacing: 24) {
        HoverActionBarContent(
            items: MessageActionModel.items(for: subject, on: .hoverRow),
            perform: { _ in }
        )
        HoverActionBarContent(
            items: MessageActionModel.items(for: subject, on: .hoverRow, quickReactionKeys: []),
            perform: { _ in }
        )
    }
    .padding(24)
}
