import Models
import SwiftUI
import Tokens

/// A label's icon: its SF Symbol, or the first letter of its name (a tag for
/// a blank name), on a rounded square in its color (MATRIX-77). Used by the
/// rail, the picker trigger, and menus.
public struct LabelIcon: View {
    let name: String
    let colorIndex: Int?
    let icon: String?
    let size: CGFloat

    public init(name: String, colorIndex: Int?, icon: String?, size: CGFloat = LabelToken.railIconSize) {
        self.name = name
        self.colorIndex = colorIndex
        self.icon = icon
        self.size = size
    }

    public init(label: ChatLabel, size: CGFloat = LabelToken.railIconSize) {
        self.init(name: label.name, colorIndex: label.colorIndex, icon: label.icon, size: size)
    }

    /// The metrics scale with `size` from the rail's 32 pt square.
    private var scale: CGFloat {
        size / LabelToken.railIconSize
    }

    private var monogram: String {
        ChatLabel(name: name).monogram
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: LabelToken.railIconCornerRadius * scale, style: .continuous)
            .fill(LabelToken.fill(for: colorIndex))
            .frame(width: size, height: size)
            .overlay {
                Group {
                    if let symbol = icon ?? (monogram.isEmpty ? "tag" : nil) {
                        Image(systemName: symbol)
                            .font(.system(size: LabelToken.railGlyphSize * scale, weight: .semibold))
                    } else {
                        Text(monogram)
                            .font(.system(size: LabelToken.railMonogramSize * scale, weight: .bold))
                    }
                }
                .foregroundStyle(LabelToken.glyph(for: colorIndex))
            }
            .accessibilityHidden(true)
    }
}

/// A space's icon on the rail (MATRIX-167): the space's picture as a rounded
/// square of the label icon's size, or the first letter of its name on a
/// tinted square when it has no picture.
///
/// The initials show while the picture loads and when the load fails.
public struct SpaceRailIcon: View {
    let space: ChatListRailSpace
    let imageLoader: ImageLoader?
    let size: CGFloat

    public init(space: ChatListRailSpace, imageLoader: ImageLoader?, size: CGFloat = LabelToken.railIconSize) {
        self.space = space
        self.imageLoader = imageLoader
        self.size = size
    }

    private var initials: LabelIcon {
        LabelIcon(
            name: space.name,
            colorIndex: space.colorIndex(paletteCount: LabelToken.palette.count),
            icon: space.monogram.isEmpty ? "square.grid.2x2" : nil,
            size: size
        )
    }

    public var body: some View {
        if let avatarUrl = space.avatarUrl {
            AvatarImage(avatarUrl: avatarUrl, imageLoader: imageLoader) {
                initials
            }
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: LabelToken.railIconCornerRadius * size / LabelToken.railIconSize,
                    style: .continuous
                )
            )
            .accessibilityHidden(true)
        } else {
            initials
        }
    }
}

/// The unread mark on a rail item: Beeper's AccountBadge (MATRIX-77). A
/// count rolls to its new value (MATRIX-193) and pops when it goes up
/// (MATRIX-225).
struct LabelBadgeView: View {
    let badge: ChatLabelBadge

    /// The value the count rolls on; zero for a dot or no mark.
    private var rollValue: Double {
        if case let .count(count) = badge {
            return UnreadCountCap.rollValue(count)
        }
        return 0
    }

    var body: some View {
        mark
            .rollingCountAnimation(rollValue)
            .badgePop(count: BadgePopRule.count(of: badge))
    }

    @ViewBuilder private var mark: some View {
        switch badge {
        case .none:
            EmptyView()
        case .dot:
            Circle()
                .fill(Color.accentColor)
                .frame(width: LabelToken.badgeDotSize, height: LabelToken.badgeDotSize)
        case let .count(count):
            Text(UnreadCountCap.text(count))
                .font(.system(size: LabelToken.badgeCountFontSize, weight: .bold))
                .rollingCountText(UnreadCountCap.rollValue(count))
                .foregroundStyle(.white)
                .padding(.horizontal, LabelToken.badgeCountHorizontalPadding)
                .frame(minWidth: LabelToken.badgeCountMinWidth, minHeight: LabelToken.badgeCountHeight)
                .background(Capsule().fill(Color.accentColor))
        }
    }
}
