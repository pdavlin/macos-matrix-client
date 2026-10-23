import Models
import SwiftUI
import Tokens

/// A round room avatar with the bridge-network badge on its bottom-right
/// corner (MATRIX-67). Shared by `ChatListRow` and `PinnedChatTile`.
struct ChatListAvatar: View {
    let model: ChatListRowModel
    let size: CGFloat
    let imageLoader: ImageLoader?

    var body: some View {
        AvatarImage(avatarUrl: model.avatarUrl, imageLoader: imageLoader) {
            ChatListAvatarPlaceholder(title: model.title, size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            if let network = model.network {
                ChatListNetworkBadge(network: network)
                    .offset(x: -ChatListToken.networkBadgeOffset, y: -ChatListToken.networkBadgeOffset)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The avatar shown while the image loads, or when the room has none: the
/// title's first letter on a neutral fill.
struct ChatListAvatarPlaceholder: View {
    let title: String
    let size: CGFloat

    private var initial: String {
        title.first { $0.isLetter || $0.isNumber }.map { String($0).uppercased() } ?? "#"
    }

    var body: some View {
        ZStack {
            Color.gray.opacity(0.45)
            Text(initial)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// A small colored squircle naming the bridged network.
///
/// Deliberately not a brand logo: Beeper's network assets are not ours to
/// copy, so each network gets a letter on a color from `badgeColor`.
struct ChatListNetworkBadge: View {
    let network: ChatListNetwork

    var body: some View {
        let size = ChatListToken.networkBadgeSize
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
