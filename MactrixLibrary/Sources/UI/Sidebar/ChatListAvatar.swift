import Models
import SwiftUI
import Tokens

/// A room avatar with the bridge-network badge on its bottom-right corner
/// (MATRIX-67). Shared by `ChatListRow`, `PinnedChatTile`, the quick
/// switcher, and the label sheet. A native Matrix chat has no badge.
///
/// MATRIX-194: a transparent ring is cut around each badge
/// (`ChatListBadgeCutout`), and `showsNetworkBadges` hides the badges.
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

    /// MATRIX-194: Settings > Appearance > "Show network badges". The sidebar
    /// sets it; other hosts keep the default, on.
    @Environment(\.showsNetworkBadges) private var showsNetworkBadges

    /// The badges the avatar draws: the model's badges, or none when the
    /// setting is off (MATRIX-194).
    static func visibleBadges(of model: ChatListRowModel, showsNetworkBadges: Bool) -> [ChatBadge] {
        showsNetworkBadges ? model.badges : []
    }

    /// Where badge `index` sits relative to the avatar's bottom-right
    /// corner. The first badge is on the corner; each further badge of a
    /// merged chat (MATRIX-141) steps toward the leading edge by
    /// `MergedChatToken.badgeStepRatio` of a badge.
    private func badgeOffset(index: Int, badgeSize: CGFloat) -> CGSize {
        CGSize(
            width: -ChatListToken.networkBadgeOffset - CGFloat(index) * badgeSize * MergedChatToken.badgeStepRatio,
            height: -ChatListToken.networkBadgeOffset
        )
    }

    var body: some View {
        let badges = Self.visibleBadges(of: model, showsNetworkBadges: showsNetworkBadges)
        let badgeSize = ChatListToken.networkBadgeSize(forAvatarSize: size)
        // MATRIX-194: the badges draw back to front, the first badge last,
        // so it is on top. Before each badge, its ring cuts a transparent
        // gap (`destinationOut`) through the avatar and the badges behind
        // it. The compositing group keeps the cut inside the avatar, so the
        // row background shows through the gap. Offsets do not change the
        // layout: the avatar stays `size` square and the row keeps its height.
        ZStack(alignment: .bottomTrailing) {
            content
                .frame(width: size, height: size)
            ForEach(Array(badges.enumerated()).reversed(), id: \.element) { index, badge in
                let offset = badgeOffset(index: index, badgeSize: badgeSize)
                ChatListBadgeCutout(badge: badge, size: badgeSize)
                    .offset(offset)
                ChatListAccountBadge(badge: badge, size: badgeSize, imageLoader: imageLoader)
                    .offset(offset)
            }
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .accessibilityHidden(true)
    }
}

/// The ring cut out around one avatar badge (MATRIX-194), so the badge reads
/// on any avatar image or color.
///
/// An opaque shape one ring wider than the badge on each side, centered on
/// the badge, drawn with `destinationOut`: it erases what the enclosing
/// compositing group drew before it. A circle for the letter badge, a
/// squircle for an account icon (MATRIX-148), so the ring has one width all
/// around.
struct ChatListBadgeCutout: View {
    let badge: ChatBadge
    /// The badge's side in points.
    let size: CGFloat

    private var ring: CGFloat {
        NetworkBadgeToken.ringWidth(forBadgeSize: size)
    }

    private var shape: AnyShape {
        if badge.account?.avatarUrl != nil {
            AnyShape(RoundedRectangle(
                cornerRadius: size * ChatListToken.networkBadgeCornerRadiusRatio + ring,
                style: .continuous
            ))
        } else {
            AnyShape(Circle())
        }
    }

    var body: some View {
        shape
            .fill(Color.black)
            .frame(width: size + 2 * ring, height: size + 2 * ring)
            .frame(width: size, height: size)
            .blendMode(.destinationOut)
            .allowsHitTesting(false)
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

/// A small colored circle naming the bridged network.
///
/// Deliberately not a brand logo: Beeper's network assets are not ours to
/// copy. MATRIX-194: the badge is the network's letter-circle SF Symbol
/// (`ChatListNetwork.badgeSymbolName`) in palette rendering, a white letter
/// on the network's tint (`badgeTint`).
///
/// MATRIX-129: the badge scales with its avatar
/// (`ChatListToken.networkBadgeSize(forAvatarSize:)`).
struct ChatListNetworkBadge: View {
    let network: ChatListNetwork
    /// The badge's side in points.
    let size: CGFloat

    var body: some View {
        Image(systemName: network.badgeSymbolName)
            .resizable()
            .symbolRenderingMode(.palette)
            .foregroundStyle(NetworkBadgeToken.glyphColor, network.badgeTint.color)
            .scaledToFit()
            .frame(width: size, height: size)
            .help(network.displayName)
    }
}

public extension EnvironmentValues {
    /// Whether chat avatars draw their network badges (MATRIX-194). The
    /// sidebar sets it from `NetworkBadgePreferences`; elsewhere it is on.
    @Entry var showsNetworkBadges = NetworkBadgePreferences.defaultValue

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

extension ChatListNetwork {
    /// The badge tint (MATRIX-194). Networks that share a letter differ by
    /// tint.
    var badgeTint: NetworkBadgeToken.Tint {
        switch self {
        case .slack: NetworkBadgeToken.slack
        case .whatsApp: NetworkBadgeToken.whatsApp
        case .signal: NetworkBadgeToken.signal
        case .discord: NetworkBadgeToken.discord
        case .telegram: NetworkBadgeToken.telegram
        case .googleChat: NetworkBadgeToken.googleChat
        case .groupMe: NetworkBadgeToken.groupMe
        case .meta: NetworkBadgeToken.meta
        case .instagram: NetworkBadgeToken.instagram
        case .facebook: NetworkBadgeToken.messenger
        case .googleMessages: NetworkBadgeToken.googleMessages
        case .linkedIn: NetworkBadgeToken.linkedIn
        case .twitter: NetworkBadgeToken.twitter
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

    private var count: Int {
        Int(clamping: unread.count)
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
            if count > 0 {
                Text(UnreadCountCap.text(count))
                    .font(.system(size: ChatListToken.unreadCountFontSize, weight: .bold))
                    .rollingCountText(UnreadCountCap.rollValue(count))
                    .foregroundStyle(.white)
                    .padding(.horizontal, ChatListToken.unreadCountHorizontalPadding)
                    .frame(minWidth: ChatListToken.unreadCountMinWidth, minHeight: ChatListToken.unreadCountMinWidth)
                    .background(Capsule().fill(capsuleFill))
            }
        }
        .rollingCountAnimation(UnreadCountCap.rollValue(count))
        // MATRIX-225: a pulse when the count goes up, on the whole mark, so
        // the capsule that appears for a first unread pops too.
        .badgePop(count: BadgePopRule.count(of: unread))
        .accessibilityHidden(true)
    }
}
