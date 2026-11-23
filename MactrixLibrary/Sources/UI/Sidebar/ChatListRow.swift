import Models
import SwiftUI
import Tokens

/// One two-line row of the sidebar chat list (MATRIX-67).
///
/// Layout follows Beeper's inbox row: the avatar with its network badge,
/// then the title and timestamp over a two-line preview with the unread count
/// on the trailing edge. The row paints no selection of its own; the sidebar
/// `List` draws the native one.
///
/// MATRIX-123: the unread or send-failure dot sits on the avatar's top-leading
/// corner, so the avatar starts at the row's leading edge. The title has
/// layout priority over the timestamp, and the timestamp never truncates.
///
/// MATRIX-222: a row with a `primaryAction` shows it as a round button on
/// its trailing edge while the pointer is over the row, as Beeper's
/// `primaryThreadAction` (Archive or Unarchive). The button floats over the
/// timestamp and the unread count, so the row keeps its height.
public struct ChatListRow: View {
    let model: ChatListRowModel
    let imageLoader: ImageLoader?
    let primaryAction: ChatListRowAction?
    /// Draws the button without a pointer, for the snapshot tests.
    let showsActionWithoutHover: Bool

    @State private var isHovering = false

    /// - Parameters:
    ///   - model: the row's content.
    ///   - imageLoader: loads the avatar.
    ///   - primaryAction: the button the row shows under the pointer, or
    ///     nil for none.
    public init(model: ChatListRowModel, imageLoader: ImageLoader?, primaryAction: ChatListRowAction? = nil) {
        self.init(model: model, imageLoader: imageLoader, primaryAction: primaryAction, showsActionWithoutHover: false)
    }

    init(model: ChatListRowModel, imageLoader: ImageLoader?, primaryAction: ChatListRowAction?, showsActionWithoutHover: Bool) {
        self.model = model
        self.imageLoader = imageLoader
        self.primaryAction = primaryAction
        self.showsActionWithoutHover = showsActionWithoutHover
    }

    private var secondaryStyle: some ShapeStyle {
        HierarchicalShapeStyle.primary.opacity(ChatListToken.previewOpacity)
    }

    @ViewBuilder
    private var indicator: some View {
        if model.hasSendFailure {
            Circle()
                .fill(Color.red)
                .frame(width: ChatListToken.indicatorDotSize, height: ChatListToken.indicatorDotSize)
        } else if model.unread.isUnread {
            Circle()
                .fill(model.unread.isMuted ? AnyShapeStyle(secondaryStyle) : AnyShapeStyle(Color.accentColor))
                .frame(width: ChatListToken.indicatorDotSize, height: ChatListToken.indicatorDotSize)
        }
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(model.title)
                .font(.system(
                    size: ChatListToken.titleFontSize,
                    weight: model.unread.isUnread ? ChatListToken.titleUnreadWeight : ChatListToken.titleReadWeight
                ))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(ChatListToken.titleLayoutPriority)

            if model.unread.isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: ChatListToken.timestampFontSize))
                    .foregroundStyle(secondaryStyle)
            }

            // MATRIX-212: the chat has a scheduled message.
            if model.hasScheduledMessages {
                Image(systemName: "clock")
                    .font(.system(size: ChatListToken.timestampFontSize))
                    .foregroundStyle(secondaryStyle)
            }

            Spacer(minLength: 4)

            if let timestamp = model.timestamp {
                Text(timestamp)
                    .font(.system(size: ChatListToken.timestampFontSize, weight: ChatListToken.timestampWeight))
                    .monospacedDigit()
                    .foregroundStyle(ChatListToken.timestampStyle)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// The preview, or MATRIX-207's inbox note in its place. The note takes
    /// the preview's secondary style, not the accent color: the accent is
    /// the selected row's background, so an accent note is not readable.
    private var previewText: Text {
        guard let note = model.inboxNote else {
            return Text(model.preview ?? "")
        }
        return Text("\(Image(systemName: "moon.zzz.fill")) \(note)")
    }

    private var previewLine: some View {
        HStack(alignment: .top, spacing: 4) {
            previewText
                .font(.system(size: ChatListToken.previewFontSize))
                .foregroundStyle(secondaryStyle)
                // Reserve both lines so every row has the same height and the
                // list does not jitter as previews change length.
                .lineLimit(ChatListToken.previewLineLimit, reservesSpace: true)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            ChatListUnreadIndicator(unread: model.unread)
        }
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ChatListAvatar(model: model, size: ChatListToken.avatarSize, imageLoader: imageLoader)
                // An overlay, not a column: the dot takes no width, so the
                // avatar keeps its place when the row turns unread.
                .overlay(alignment: .topLeading) {
                    indicator
                }

            VStack(alignment: .leading, spacing: ChatListToken.lineSpacing) {
                titleLine
                previewLine
            }
            .padding(.leading, ChatListToken.avatarTextSpacing)
        }
        .padding(.vertical, ChatListToken.rowVerticalPadding)
        .padding(.horizontal, ChatListToken.rowHorizontalPadding)
        .contentShape(Rectangle())
        // An overlay, so the button takes no space and the row keeps its
        // height.
        .overlay(alignment: .trailing) {
            if let primaryAction, isHovering || showsActionWithoutHover {
                ChatListRowActionButton(action: primaryAction)
            }
        }
        .onHover { isHovering = $0 }
        .help(model.helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.preview ?? "")
        .modifier(ChatListRowAccessibilityAction(action: primaryAction))
    }
}

/// The button a chat-list row shows under the pointer (MATRIX-222): a
/// title for the tooltip and VoiceOver, a symbol, and what a click does.
public struct ChatListRowAction {
    public let title: String
    public let systemImage: String
    public let perform: @MainActor () -> Void

    public init(title: String, systemImage: String, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.perform = perform
    }
}

/// The round hover button of a chat-list row (MATRIX-222).
///
/// Opaque, with a hairline border and a soft shadow, as the timeline's
/// hover action bar: the row under it can be the accent-filled selection,
/// and the list scrolls, so no glass (CLAUDE.md hard rule 2).
struct ChatListRowActionButton: View {
    let action: ChatListRowAction

    @State private var isHovering = false

    var body: some View {
        Button {
            action.perform()
        } label: {
            Image(systemName: action.systemImage)
                .font(.system(size: ChatListToken.rowActionIconSize, weight: .semibold))
                .foregroundStyle(isHovering ? Color.accentColor : Color(PlatformColor.secondaryLabelColor))
                .frame(width: ChatListToken.rowActionSize, height: ChatListToken.rowActionSize)
                .background(
                    Circle()
                        .fill(Color(PlatformColor.controlBackgroundColor))
                        .stroke(Color(PlatformColor.separatorColor), lineWidth: BubbleToken.hoverBorderWidth)
                        .shadow(color: .black.opacity(ChatListToken.rowActionShadowOpacity), radius: ChatListToken.rowActionShadowRadius)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(action.title)
        .accessibilityLabel(action.title)
        .onHover { isHovering = $0 }
    }
}

/// The row's hover action as a VoiceOver action: the row hides its
/// children from accessibility, so the button cannot be reached on its own.
private struct ChatListRowAccessibilityAction: ViewModifier {
    let action: ChatListRowAction?

    func body(content: Content) -> some View {
        if let action {
            content.accessibilityAction(named: Text(action.title)) {
                action.perform()
            }
        } else {
            content
        }
    }
}

#Preview {
    List {
        ChatListRow(
            model: ChatListRowModel(
                id: "!a",
                title: "Alice",
                isDirect: true,
                preview: "See you at the station at six, bring the tickets",
                timestamp: "3:42 PM",
                unread: ChatListUnread(count: 2, isUnread: true),
                network: .whatsApp
            ),
            imageLoader: nil
        )
        ChatListRow(
            model: ChatListRowModel(
                id: "!b",
                title: "Release planning",
                preview: "You: Shipping Thursday",
                timestamp: "Tue"
            ),
            imageLoader: nil
        )
    }
    .listStyle(.sidebar)
    .frame(width: 320)
}
