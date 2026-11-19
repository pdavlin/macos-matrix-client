import SwiftUI
import Tokens

/// The composer surface and its action buttons (MATRIX-195): the field (the
/// reply and edit bars, the attachments, the text view) on a rounded glass
/// rect, and the attach, emoji, and send buttons beside it.
///
/// Glass rules (contract hard rule 2, and the 2026-11-18 §11 row):
/// - The composer is chrome. It floats over the bottom of the timeline, and
///   the rows scroll under it: the one glass overlay over the timeline
///   (MATRIX-198, §11 2026-11-18).
/// - The field and the buttons are siblings in one `GlassEffectContainer`.
///   No glass draws on top of other glass, and the shapes can morph.
/// - Idle buttons join one capsule through `glassEffectUnion`. The send
///   button is idle while the composer is empty. With content it leaves the
///   capsule and takes the accent tint.
/// - The send button stays in the layout in both states, so the field width
///   does not change when the first character is typed.
/// - With Reduce Transparency the view draws an opaque field and plain
///   buttons, with no glass. With Reduce Motion the state change is instant.
///
/// The view only draws. The composer owns the text, the attachments, and the
/// send, and it reports them through the parameters and the closures.
public struct ComposerChrome<Field: View>: View {
    /// What the buttons do when they are clicked.
    public struct Actions {
        public var attach: () -> Void
        public var emoji: () -> Void
        public var send: () -> Void

        public init(attach: @escaping () -> Void, emoji: @escaping () -> Void, send: @escaping () -> Void) {
            self.attach = attach
            self.emoji = emoji
            self.send = send
        }
    }

    /// The glass identities in the container's namespace.
    private enum GlassID: Hashable, Sendable {
        case field
        case attach
        case emoji
        case send
        /// The union of the idle buttons.
        case idle
    }

    /// The gap between the field and the buttons, and between the buttons.
    /// The container uses the same value, so the shapes are apart at rest
    /// and blend while they morph.
    static var spacing: CGFloat { 6 }

    /// The field's corner radius.
    static var fieldCornerRadius: CGFloat { 16 }

    /// The padding around a button's symbol. The same as the text view's
    /// inset (`DynamicTextView.padding`), so a button is as tall as a field
    /// with one line of text.
    static var symbolPadding: CGFloat { 10 }

    /// The smallest symbol box, so narrow symbols make a regular capsule.
    static var symbolSize: CGFloat { 16 }

    let hasContent: Bool
    let canAttach: Bool
    let canPickEmoji: Bool
    let canSend: Bool
    let isEditing: Bool
    let usesGlass: Bool
    let actions: Actions
    let field: Field
    /// False only in snapshot tests: `NSView.cacheDisplay` draws nothing at
    /// all for a view that holds tinted glass (macOS 27 beta SDK), so the
    /// tests draw the send capsule untinted with an accent symbol.
    var tintsSend = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    /// - Parameters:
    ///   - hasContent: The composer holds text or attachments. The send button
    ///     is prominent.
    ///   - canAttach: The attach button is enabled.
    ///   - canPickEmoji: The emoji button is enabled.
    ///   - canSend: The send button is enabled.
    ///   - isEditing: The composer edits a message. The send button saves.
    ///   - usesGlass: False when Reduce Transparency is on. The view then
    ///     draws no glass.
    ///   - actions: The button actions.
    ///   - field: The composer content, without a background.
    public init(
        hasContent: Bool,
        canAttach: Bool,
        canPickEmoji: Bool,
        canSend: Bool,
        isEditing: Bool,
        usesGlass: Bool,
        actions: Actions,
        @ViewBuilder field: () -> Field
    ) {
        self.hasContent = hasContent
        self.canAttach = canAttach
        self.canPickEmoji = canPickEmoji
        self.canSend = canSend
        self.isEditing = isEditing
        self.usesGlass = usesGlass
        self.actions = actions
        self.field = field()
    }

    public var body: some View {
        if usesGlass {
            glassBody
        } else {
            opaqueBody
        }
    }

    // MARK: - Glass

    private var glassBody: some View {
        GlassEffectContainer(spacing: Self.spacing) {
            HStack(alignment: .bottom, spacing: Self.spacing) {
                field
                    .glassEffect(in: .rect(cornerRadius: Self.fieldCornerRadius))
                    .glassEffectID(GlassID.field, in: glassNamespace)
                HStack(spacing: Self.spacing) {
                    attachButton
                        .glassEffect(.regular.interactive(canAttach), in: .capsule)
                        .glassEffectUnion(id: GlassID.idle, namespace: glassNamespace)
                        .glassEffectID(GlassID.attach, in: glassNamespace)
                    emojiButton
                        .glassEffect(.regular.interactive(canPickEmoji), in: .capsule)
                        .glassEffectUnion(id: GlassID.idle, namespace: glassNamespace)
                        .glassEffectID(GlassID.emoji, in: glassNamespace)
                    sendButton
                        .glassEffect(sendGlass, in: .capsule)
                        .glassEffectUnion(id: hasContent ? nil : GlassID.idle, namespace: glassNamespace)
                        .glassEffectID(GlassID.send, in: glassNamespace)
                }
                // Only the buttons animate: the field's own changes (an
                // attachment strip, a reply bar) keep their instant layout.
                .animation(MotionToken.animation(MotionToken.standard(), reduceMotion: reduceMotion), value: hasContent)
            }
        }
    }

    private var sendGlass: Glass {
        hasContent && tintsSend
            ? .regular.tint(.accentColor).interactive(canSend)
            : .regular.interactive(canSend)
    }

    /// The same view with an untinted send capsule, for snapshot tests.
    func untintedForSnapshot() -> Self {
        var copy = self
        copy.tintsSend = false
        return copy
    }

    // MARK: - Opaque (Reduce Transparency)

    private var opaqueBody: some View {
        HStack(alignment: .bottom, spacing: Self.spacing) {
            field
                .background(
                    Color(PlatformColor.textBackgroundColor),
                    in: .rect(cornerRadius: Self.fieldCornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.fieldCornerRadius)
                        .stroke(Color(PlatformColor.separatorColor), lineWidth: 1)
                )
            HStack(spacing: Self.spacing) {
                attachButton
                emojiButton
                sendButton
            }
        }
    }

    // MARK: - Buttons

    private var attachButton: some View {
        symbolButton("paperclip", label: "Attach files", action: actions.attach)
            .foregroundStyle(.secondary)
            .disabled(!canAttach)
    }

    private var emojiButton: some View {
        symbolButton("face.smiling", label: "Emoji & Symbols", action: actions.emoji)
            .foregroundStyle(.secondary)
            .disabled(!canPickEmoji)
    }

    private var sendButton: some View {
        symbolButton(
            isEditing ? "checkmark" : "arrow.up",
            label: isEditing ? "Save edit" : "Send",
            action: actions.send
        )
        .fontWeight(.semibold)
        .foregroundStyle(sendForeground)
        .disabled(!canSend)
    }

    /// White on the accent glass, the accent on untinted glass and on the
    /// opaque field, and secondary while the send button is idle.
    private var sendForeground: AnyShapeStyle {
        guard hasContent else { return AnyShapeStyle(.secondary) }
        return usesGlass && tintsSend ? AnyShapeStyle(.white) : AnyShapeStyle(.tint)
    }

    private func symbolButton(
        _ systemImage: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .frame(minWidth: Self.symbolSize, minHeight: Self.symbolSize)
                .padding(Self.symbolPadding)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
    }
}

#Preview {
    ComposerChrome(
        hasContent: true,
        canAttach: true,
        canPickEmoji: true,
        canSend: true,
        isEditing: false,
        usesGlass: true,
        actions: .init(attach: {}, emoji: {}, send: {})
    ) {
        Text("Lunch at noon?")
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding()
    .frame(width: 420)
}
