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
///
/// The pointer is the pointing hand over the whole capsule (MATRIX-205).
/// The thread pill (`MessageThreadSummary`) uses this style too, so it gets
/// the same pointer.
struct ReactionChipButtonStyle: ButtonStyle {
    /// True when the account's own user is one of the reaction's senders.
    let isOwn: Bool

    func makeBody(configuration: Configuration) -> some View {
        ReactionChip(label: configuration.label, isOwn: isOwn, isPressed: configuration.isPressed)
    }
}

struct ReactionChip<Label: View>: View {
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
            .linkPointerStyle()
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

public extension EnvironmentValues {
    /// The shortcode of a custom emoji reaction key, an `mxc://` URL, without
    /// its colons, or nil when it is not known (MATRIX-166). The timeline
    /// container sets it from the room's image packs. The chip's tooltip and
    /// accessibility label name the emoji with it. The lookup must be
    /// synchronous and cheap: a chip calls it on each draw.
    @Entry var reactionEmojiName: (@MainActor (String) -> String?)?
}

public struct MessageReactionView<Reaction: Models.Reaction>: View {
    let reaction: Reaction
    let active: Binding<Bool>
    let imageLoader: ImageLoader?
    let ownUserId: String
    let displayName: (String) -> String?

    @Environment(\.reactionEmojiName) private var customEmojiName

    /// - Parameters:
    ///   - reaction: The reaction the chip shows.
    ///   - active: Whether the account's own user is a sender. A set toggles
    ///     the reaction with the same key.
    ///   - imageLoader: Loads the image of an `mxc://` key (MATRIX-154). Nil
    ///     draws the generic glyph for such a key.
    ///   - ownUserId: The account's own user ID. The tooltip names it "You".
    ///   - displayName: The display name of a sender's user ID, from data
    ///     the caller already has, or nil. The tooltip then shows the
    ///     localpart of the user ID (MATRIX-166).
    public init(
        reaction: Reaction,
        active: Binding<Bool>,
        imageLoader: ImageLoader? = nil,
        ownUserId: String = "",
        displayName: @escaping (String) -> String? = { _ in nil }
    ) {
        self.reaction = reaction
        self.active = active
        self.imageLoader = imageLoader
        self.ownUserId = ownUserId
        self.displayName = displayName
    }

    /// Who posted the reaction. See `ReactionSenderSummary` for the rule.
    var senderSummary: ReactionSenderSummary {
        ReactionSenderSummary(senderIds: reaction.senders.map(\.senderId), ownUserId: ownUserId, displayName: displayName)
    }

    /// The name of a custom emoji key when it is known: the shortcode from
    /// the room's image packs for an `mxc://` key, or the name of a `:name:`
    /// key. Nil for a Unicode key, and for an image with no known shortcode.
    var emojiName: String? {
        switch ReactionKeyKind(key: reaction.key) {
        case let .image(mxcUrl): customEmojiName?(mxcUrl)
        case let .shortcode(name): name
        case .unicode: nil
        }
    }

    /// The system tooltip of the chip on the Mac: the people who posted the
    /// reaction, after the custom emoji's name when it is known.
    var toolTipText: String {
        senderSummary.tooltip(emojiName: emojiName)
    }

    /// The chip's accessibility label: the key, the tally, and the people.
    var accessibilityText: String {
        senderSummary.accessibilityLabel(keyName: emojiName ?? ReactionKeyKind(key: reaction.key).spokenName)
    }

    private var count: Int {
        reaction.senders.count
    }

    public var body: some View {
        chip
            .accessibilityLabel(Text(verbatim: accessibilityText))
            .reactionChipToolTip(toolTipText)
    }

    private var chip: some View {
        Toggle(isOn: active, label: {
            HStack(spacing: 0) {
                ReactionKeyLabel(key: reaction.key, imageLoader: imageLoader)
                countLabel
                    .padding(.horizontal, DensityToken.reactionCountPadding)
            }
            .padding(DensityToken.reactionPadding)
        })
        .toggleStyle(MessageReactionToggleStyle())
        .rollingCountAnimation(Double(count))
    }

    /// The tally. It is semibold for the account's own reaction. A hidden
    /// semibold copy sets the width for both weights, so the chip's width
    /// depends on the digit count only, as `ReactionPillGeometry` assumes: a
    /// toggle never resizes the chip or the strip.
    ///
    /// MATRIX-193: the tally rolls to its new value. Both copies use tabular
    /// digits, so 1 to 2 keeps the chip's width; when the tally gains a
    /// digit, the animation on the chip eases the capsule to its new width.
    private var countLabel: some View {
        Text("\(count)")
            .fontWeight(.semibold)
            .monospacedDigit()
            .hidden()
            .overlay {
                Text("\(count)")
                    .fontWeight(active.wrappedValue ? .semibold : .regular)
                    .rollingCountText(Double(count))
            }
    }
}

#Preview {
    @Previewable @State var active = false
    MessageReactionView(reaction: MockReaction(), active: $active)
        .padding()
}
