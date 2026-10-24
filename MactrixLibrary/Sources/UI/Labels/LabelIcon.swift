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

/// The unread mark on a rail item: Beeper's AccountBadge (MATRIX-77).
struct LabelBadgeView: View {
    let badge: ChatLabelBadge

    var body: some View {
        switch badge {
        case .none:
            EmptyView()
        case .dot:
            Circle()
                .fill(Color.accentColor)
                .frame(width: LabelToken.badgeDotSize, height: LabelToken.badgeDotSize)
        case let .count(count):
            Text(count > 99 ? "99+" : "\(count)")
                .font(.system(size: LabelToken.badgeCountFontSize, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, LabelToken.badgeCountHorizontalPadding)
                .frame(minWidth: LabelToken.badgeCountMinWidth, minHeight: LabelToken.badgeCountHeight)
                .background(Capsule().fill(Color.accentColor))
        }
    }
}
