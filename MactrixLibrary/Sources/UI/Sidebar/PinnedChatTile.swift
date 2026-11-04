import Models
import SwiftUI
import Tokens

/// A favourite room in the pinned grid above the chat list (MATRIX-67).
///
/// The grid sits outside the `List` selection model, so a tile is a button
/// that reports the tap and draws its own subtle selected background. The
/// unread count rides on the avatar's top-right corner.
public struct PinnedChatTile: View {
    let model: ChatListRowModel
    let isSelected: Bool
    let imageLoader: ImageLoader?
    let action: () -> Void

    public init(model: ChatListRowModel, isSelected: Bool, imageLoader: ImageLoader?, action: @escaping () -> Void) {
        self.model = model
        self.isSelected = isSelected
        self.imageLoader = imageLoader
        self.action = action
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ChatListToken.pinnedSelectedCornerRadius, style: .continuous)
    }

    @ViewBuilder
    private var unreadMark: some View {
        if model.unread.count > 0 || model.unread.hasMention {
            ChatListUnreadIndicator(unread: model.unread)
        } else if model.unread.isUnread {
            Circle()
                .fill(model.unread.isMuted ? Color.secondary : Color.accentColor)
                .frame(width: ChatListToken.pinnedUnreadDotSize, height: ChatListToken.pinnedUnreadDotSize)
        }
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: ChatListToken.pinnedTitleSpacing) {
                ChatListAvatar(model: model, size: ChatListToken.pinnedAvatarSize, imageLoader: imageLoader)
                    .overlay(alignment: .topTrailing) {
                        unreadMark
                            .offset(x: ChatListToken.pinnedUnreadOffset, y: -ChatListToken.pinnedUnreadOffset)
                    }

                Text(model.title)
                    .font(.system(size: ChatListToken.pinnedTitleFontSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.top, ChatListToken.pinnedTileTopPadding)
            .padding(.horizontal, ChatListToken.pinnedTileHorizontalPadding)
            .padding(.bottom, ChatListToken.pinnedTileBottomPadding)
            .frame(minWidth: ChatListToken.pinnedTileMinWidth, maxWidth: .infinity)
            .background {
                if isSelected {
                    tileShape.fill(Color.primary.opacity(ChatListToken.pinnedSelectedOpacity))
                }
            }
            .contentShape(tileShape)
        }
        .buttonStyle(.plain)
        .help(model.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    HStack(spacing: 0) {
        PinnedChatTile(
            model: ChatListRowModel(
                id: "!a",
                title: "Alice",
                isDirect: true,
                unread: ChatListUnread(count: 3, isUnread: true),
                network: .signal
            ),
            isSelected: false,
            imageLoader: nil,
            action: {}
        )
        PinnedChatTile(
            model: ChatListRowModel(id: "!b", title: "Family"),
            isSelected: true,
            imageLoader: nil,
            action: {}
        )
    }
    .frame(width: 240)
    .padding()
}
