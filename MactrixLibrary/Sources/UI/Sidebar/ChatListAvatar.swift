import Models
import SwiftUI
import Tokens

/// A room avatar with the bridge-network badge on its bottom-right corner
/// (MATRIX-67). Shared by `ChatListRow`, `PinnedChatTile`, the quick
/// switcher, and the label sheet.
///
/// MATRIX-129: the view draws `ChatListRowModel.avatarChoice` and holds no
/// rule of its own. An image or initials is clipped to a circle; a group's
/// bubble cluster is not clipped, so no bubble is cut at the edge.
struct ChatListAvatar: View {
    let model: ChatListRowModel
    let size: CGFloat
    let imageLoader: ImageLoader?

    @ViewBuilder
    private var content: some View {
        switch model.avatarChoice {
        case let .image(url: url, placeholder: placeholder):
            AvatarImage(avatarUrl: url, imageLoader: imageLoader) {
                ChatListAvatarPlaceholder(initials: placeholder, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        case let .cluster(heroes: heroes):
            ChatListAvatarClusterView(
                cluster: ChatListAvatarCluster(
                    heroes: heroes,
                    otherMemberCount: model.otherMemberCount,
                    mode: ChatListAvatarClusterView.mode(forSize: size)
                ),
                size: size,
                imageLoader: imageLoader
            )
        case let .initials(initials):
            ChatListAvatarPlaceholder(initials: initials, size: size)
                .frame(width: size, height: size)
                .clipShape(Circle())
        }
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                let badges = model.badges
                let badgeSize = ChatListToken.networkBadgeSize(forAvatarSize: size)
                if badges.count > 1 {
                    // MATRIX-141: a merged chat's networks and accounts.
                    ChatListNetworkBadgeStack(badges: badges, size: badgeSize, imageLoader: imageLoader)
                        .offset(x: -ChatListToken.networkBadgeOffset, y: -ChatListToken.networkBadgeOffset)
                } else if let badge = badges.first {
                    ChatListAccountBadge(badge: badge, size: badgeSize, imageLoader: imageLoader)
                        .offset(x: -ChatListToken.networkBadgeOffset, y: -ChatListToken.networkBadgeOffset)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Colored initials: white letters on a palette gradient (MATRIX-129).
///
/// Shown when a room or person has no image, and while an image loads. The
/// caller clips it to a circle. The letters and the palette slot come from
/// `Models.ChatListInitials`.
struct ChatListAvatarPlaceholder: View {
    let initials: ChatListInitials
    /// The circle's diameter. It sets the letter size.
    let size: CGFloat

    private var fontSize: CGFloat {
        let ratio = initials.text.count > 1 ? ChatListToken.initialsDoubleFontRatio : ChatListToken.initialsSingleFontRatio
        return size * ratio
    }

    var body: some View {
        ZStack {
            AvatarPaletteToken.gradient(atSlot: initials.paletteIndex)
            Text(initials.text)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(AvatarPaletteToken.textColor)
        }
    }
}

/// A small colored squircle naming the bridged network.
///
/// Deliberately not a brand logo: Beeper's network assets are not ours to
/// copy, so each network gets a letter on a color from `badgeColor`.
///
/// MATRIX-129: the badge scales with its avatar
/// (`ChatListToken.networkBadgeSize(forAvatarSize:)`).
struct ChatListNetworkBadge: View {
    let network: ChatListNetwork
    /// The badge's side in points.
    let size: CGFloat

    var body: some View {
        Text(network.badgeGlyph)
            .font(.system(size: size * 0.6, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(
                    cornerRadius: size * ChatListToken.networkBadgeCornerRadiusRatio,
                    style: .continuous
                )
                .fill(network.badgeColor)
            )
            .help(network.displayName)
    }
}

public extension EnvironmentValues {
    /// Loads the account icons of badges outside an avatar (MATRIX-148): the
    /// merged timeline's source notes and the composer's target chip. Nil
    /// draws the network letter.
    @Entry var chatBadgeImageLoader: (any ImageLoader)?
}

/// The avatar badge of one chat (MATRIX-148): the icon of the chat's account
/// (a Slack workspace) when it has one, else the network's letter.
///
/// The letter badge shows while the icon loads and when the load fails, so
/// the badge never is empty. The badge has the same size in both cases.
struct ChatListAccountBadge: View {
    let network: ChatListNetwork?
    let account: ChatAccount?
    /// The badge's side in points.
    let size: CGFloat
    let imageLoader: ImageLoader?

    init(network: ChatListNetwork?, account: ChatAccount?, size: CGFloat, imageLoader: ImageLoader?) {
        self.network = network
        self.account = account
        self.size = size
        self.imageLoader = imageLoader
    }

    init(badge: ChatBadge, size: CGFloat, imageLoader: ImageLoader?) {
        self.init(network: badge.network, account: badge.account, size: size, imageLoader: imageLoader)
    }

    private var helpText: String {
        [network?.displayName, account?.name].compactMap(\.self).joined(separator: " • ")
    }

    var body: some View {
        if let iconUrl = account?.avatarUrl {
            AvatarImage(avatarUrl: iconUrl, imageLoader: imageLoader) {
                letterBadge
            }
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(cornerRadius: size * ChatListToken.networkBadgeCornerRadiusRatio, style: .continuous)
            )
            .help(helpText)
        } else {
            letterBadge
        }
    }

    @ViewBuilder private var letterBadge: some View {
        if let network {
            ChatListNetworkBadge(network: network, size: size)
        } else {
            Color.clear.frame(width: size, height: size)
        }
    }
}

/// Several network badges in a row on the avatar's bottom-right corner, for
/// a merged chat (MATRIX-141).
///
/// The first network sits where a single badge sits and draws on top; each
/// further badge steps toward the leading edge by
/// `MergedChatToken.badgeStepRatio` of a badge and hides behind the one
/// after it.
struct ChatListNetworkBadgeStack: View {
    /// The badges, first on top. The caller caps the count
    /// (`ChatListRowModel.badges`).
    let badges: [ChatBadge]
    /// Each badge's side in points.
    let size: CGFloat
    let imageLoader: ImageLoader?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(badges.enumerated()), id: \.element) { index, badge in
                ChatListAccountBadge(badge: badge, size: size, imageLoader: imageLoader)
                    .offset(x: -CGFloat(index) * size * MergedChatToken.badgeStepRatio)
                    .zIndex(Double(badges.count - index))
            }
        }
    }
}

extension ChatListNetwork {
    /// The letter drawn on the badge.
    var badgeGlyph: String {
        switch self {
        case .slack: "S"
        case .whatsApp: "W"
        case .signal: "S"
        case .discord: "D"
        case .telegram: "T"
        case .googleChat: "G"
        case .groupMe: "G"
        case .meta: "M"
        case .instagram: "I"
        case .facebook: "F"
        case .googleMessages: "M"
        case .linkedIn: "in"
        case .twitter: "X"
        }
    }

    /// The badge fill. Networks that share a letter differ by color.
    var badgeColor: Color {
        switch self {
        case .slack: Color(red: 0.29, green: 0.08, blue: 0.29)
        case .whatsApp: Color(red: 0.15, green: 0.70, blue: 0.40)
        case .signal: Color(red: 0.23, green: 0.46, blue: 0.94)
        case .discord: Color(red: 0.35, green: 0.40, blue: 0.95)
        case .telegram: Color(red: 0.15, green: 0.65, blue: 0.89)
        case .googleChat: Color(red: 0.00, green: 0.51, blue: 0.18)
        case .groupMe: Color(red: 0.00, green: 0.69, blue: 0.94)
        case .meta: Color(red: 0.03, green: 0.40, blue: 1.00)
        case .instagram: Color(red: 0.89, green: 0.25, blue: 0.37)
        case .facebook: Color(red: 0.00, green: 0.52, blue: 1.00)
        case .googleMessages: Color(red: 0.10, green: 0.45, blue: 0.91)
        case .linkedIn: Color(red: 0.04, green: 0.40, blue: 0.76)
        case .twitter: Color(red: 0.08, green: 0.08, blue: 0.08)
        }
    }
}

/// The unread count capsule, preceded by an "@" when the room mentions the
/// user. Draws nothing for a read room.
struct ChatListUnreadIndicator: View {
    let unread: ChatListUnread

    @Environment(\.backgroundProminence) private var backgroundProminence

    /// On a selected sidebar row the selection is accent-filled, so accent
    /// marks would vanish into it.
    private var onAccent: Bool {
        backgroundProminence == .increased
    }

    private var countText: String {
        unread.count > 99 ? "99+" : "\(unread.count)"
    }

    private var capsuleFill: Color {
        if unread.isMuted {
            return Color.primary.opacity(ChatListToken.mutedCountOpacity)
        }
        return onAccent ? Color.white.opacity(ChatListToken.selectedRowCountOpacity) : Color.accentColor
    }

    var body: some View {
        HStack(spacing: 3) {
            if unread.hasMention {
                Text("@")
                    .font(.system(size: ChatListToken.mentionGlyphFontSize, weight: .bold))
                    .foregroundStyle(onAccent ? Color.white : Color.accentColor)
            }
            if unread.count > 0 {
                Text(countText)
                    .font(.system(size: ChatListToken.unreadCountFontSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, ChatListToken.unreadCountHorizontalPadding)
                    .frame(minWidth: ChatListToken.unreadCountMinWidth, minHeight: ChatListToken.unreadCountMinWidth)
                    .background(Capsule().fill(capsuleFill))
            }
        }
        .accessibilityHidden(true)
    }
}
