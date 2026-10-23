import Models
import SwiftUI
import Tokens

/// One two-line row of the sidebar chat list (MATRIX-67).
///
/// Layout follows Beeper's inbox row: an indicator column (unread or
/// send-failure dot), the avatar with its network badge, then the title and
/// timestamp over a two-line preview with the unread count on the trailing
/// edge. The row paints no selection of its own; the sidebar `List` draws the
/// native one.
public struct ChatListRow: View {
    let model: ChatListRowModel
    let imageLoader: ImageLoader?

    public init(model: ChatListRowModel, imageLoader: ImageLoader?) {
        self.model = model
        self.imageLoader = imageLoader
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

            if model.unread.isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: ChatListToken.timestampFontSize))
                    .foregroundStyle(secondaryStyle)
            }

            Spacer(minLength: 4)

            if let timestamp = model.timestamp {
                Text(timestamp)
                    .font(.system(size: ChatListToken.timestampFontSize))
                    .foregroundStyle(HierarchicalShapeStyle.primary.opacity(ChatListToken.timestampOpacity))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var previewLine: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(model.preview ?? "")
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
            indicator
                .frame(width: ChatListToken.indicatorColumnWidth)

            ChatListAvatar(model: model, size: ChatListToken.avatarSize, imageLoader: imageLoader)

            VStack(alignment: .leading, spacing: ChatListToken.lineSpacing) {
                titleLine
                previewLine
            }
            .padding(.leading, ChatListToken.avatarTextSpacing)
        }
        .padding(.vertical, ChatListToken.rowVerticalPadding)
        .padding(.horizontal, ChatListToken.rowHorizontalPadding)
        .contentShape(Rectangle())
        .help(model.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityValue(model.preview ?? "")
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
