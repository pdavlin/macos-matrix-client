import Models
import SwiftUI
import Tokens

/// The reaction chip's toggle (MATRIX-135). A click flips the toggle; the
/// look lives in `ReactionChipButtonStyle`, which knows the pressed state.
struct MessageReactionToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(
            action: { configuration.isOn.toggle() },
            label: { configuration.label }
        )
        .buttonStyle(ReactionChipButtonStyle(isOwn: configuration.isOn))
    }
}

/// Draws a reaction chip: a capsule with an accent tint and ring for the
/// account's own reaction, or a quiet fill with a separator ring on hover for
/// another reaction. A press scales the chip down; the release pops it back.
///
/// Every change here is a fill, a stroke, or a scale transform, so the chip's
/// frame (and the timeline row's measured height) never changes with state.
struct ReactionChipButtonStyle: ButtonStyle {
    /// True when the account's own user is one of the reaction's senders.
    let isOwn: Bool

    func makeBody(configuration: Configuration) -> some View {
        ReactionChip(label: configuration.label, isOwn: isOwn, isPressed: configuration.isPressed)
    }
}

private struct ReactionChip<Label: View>: View {
    let label: Label
    let isOwn: Bool
    let isPressed: Bool

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fill: AnyShapeStyle {
        isOwn
            ? AnyShapeStyle(Color.accentColor.opacity(ReactionToken.ownFillOpacity))
            : AnyShapeStyle(Color.gray.quaternary)
    }

    private var ring: Color {
        isOwn ? .accentColor : Color(PlatformColor.separatorColor)
    }

    /// The own reaction always shows its ring; another reaction shows it only
    /// under the pointer.
    private var showsRing: Bool {
        isOwn || hovering
    }

    /// Press-in follows the house curve at hover speed; the release springs.
    private var pressAnimation: Animation {
        isPressed ? MotionToken.standard(duration: MotionToken.hoverDuration) : MotionToken.pop
    }

    var body: some View {
        label
            .background(Capsule().fill(fill))
            .overlay {
                Capsule()
                    .strokeBorder(ring, lineWidth: ReactionToken.ringWidth)
                    .opacity(showsRing ? 1 : 0)
            }
            .contentShape(Capsule())
            .scaleEffect(isPressed ? MotionToken.pressedScale : 1)
            .animation(MotionToken.animation(pressAnimation, reduceMotion: reduceMotion), value: isPressed)
            .animation(
                MotionToken.animation(MotionToken.standard(duration: MotionToken.hoverDuration), reduceMotion: reduceMotion),
                value: hovering
            )
            .animation(MotionToken.animation(MotionToken.standard(), reduceMotion: reduceMotion), value: isOwn)
            .onHover { hover in
                hovering = hover
            }
    }
}

public struct MessageReactionView<Reaction: Models.Reaction>: View {
    let reaction: Reaction
    let active: Binding<Bool>

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(reaction: Reaction, active: Binding<Bool>) {
        self.reaction = reaction
        self.active = active
    }

    var helpText: String {
        let sendersString = reaction.senders.prefix(5)
            .map(\.senderId)
            .joined(separator: ", ")

        return "Reacted by \(sendersString)"
    }

    private var count: Int {
        reaction.senders.count
    }

    public var body: some View {
        Toggle(isOn: active, label: {
            HStack(spacing: 0) {
                Text(reaction.key)
                countLabel
                    .padding(.horizontal, DensityToken.reactionCountPadding)
            }
            .padding(DensityToken.reactionPadding)
        })
        .toggleStyle(MessageReactionToggleStyle())
        .help(helpText)
    }

    /// The tally. It is semibold for the account's own reaction. A hidden
    /// semibold copy sets the width for both weights, so the chip's width
    /// depends on the digits only, as `ReactionPillGeometry` assumes: a
    /// toggle never resizes the chip or the strip.
    private var countLabel: some View {
        Text("\(count)")
            .fontWeight(.semibold)
            .hidden()
            .overlay {
                Text("\(count)")
                    .fontWeight(active.wrappedValue ? .semibold : .regular)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(MotionToken.animation(MotionToken.standard(), reduceMotion: reduceMotion), value: count)
            }
    }
}

#Preview {
    @Previewable @State var active = false
    MessageReactionView(reaction: MockReaction(), active: $active)
        .padding()
}
