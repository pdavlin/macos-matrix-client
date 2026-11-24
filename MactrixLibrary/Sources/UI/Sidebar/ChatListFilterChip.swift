import Models
import SwiftUI
import Tokens

/// The active filter chip in the sidebar header (MATRIX-226), after
/// Indigo's `NetworkFilterChip`: the filter's symbol and name and a clear
/// mark on a capsule of tinted glass, `.regular.tint(color).interactive()`.
/// A click goes back to the Inbox.
///
/// The chip sits in the header above the chat list, on the navigation
/// layer, never over the list rows (CLAUDE.md hard rule 2). With Reduce
/// Transparency it is an opaque capsule in the same color.
public struct ChatListFilterChip: View {
    let filter: ChatListActiveFilter
    let usesGlass: Bool
    let clear: () -> Void

    /// False draws the glass untinted. `NSView.cacheDisplay` draws nothing
    /// for tinted glass, so the snapshot tests use it (as MATRIX-195 does).
    private var tintsGlass = true

    static var height: CGFloat { 24 }
    static var symbolSize: CGFloat { 11 }
    static var titleSize: CGFloat { 12 }
    static var spacing: CGFloat { 5 }
    static var leadingPadding: CGFloat { 9 }
    static var trailingPadding: CGFloat { 6 }

    /// - Parameters:
    ///   - filter: what the chip names (`ChatListActiveFilter.chip`).
    ///   - usesGlass: false when Reduce Transparency is on. The chip is then
    ///     an opaque capsule.
    ///   - clear: goes back to the Inbox.
    public init(filter: ChatListActiveFilter, usesGlass: Bool, clear: @escaping () -> Void) {
        self.filter = filter
        self.usesGlass = usesGlass
        self.clear = clear
    }

    public var body: some View {
        if usesGlass {
            button
                .glassEffect(tintsGlass ? .regular.tint(tint).interactive() : .regular.interactive(), in: .capsule)
        } else {
            button
                .background(tint, in: .capsule)
        }
    }

    private var button: some View {
        Button(action: clear) {
            HStack(spacing: Self.spacing) {
                Image(systemName: filter.systemImage)
                    .font(.system(size: Self.symbolSize, weight: .semibold))
                Text(filter.title)
                    .font(.system(size: Self.titleSize, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: Self.symbolSize))
                    .opacity(0.75)
            }
            .foregroundStyle(foreground)
            .padding(.leading, Self.leadingPadding)
            .padding(.trailing, Self.trailingPadding)
            .frame(height: Self.height)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("Show the Inbox")
        .accessibilityLabel("Filter: \(filter.title)")
        .accessibilityHint("Shows the Inbox")
    }

    /// The label's or the space's color, or the accent.
    private var tint: Color {
        switch filter.tint {
        case .accent: Color.accentColor
        case let .palette(index): LabelToken.fill(for: index)
        }
    }

    /// White on a color, as on a label's square (`LabelToken.glyph`); the
    /// primary color on the neutral fill of a label with no color and on
    /// untinted glass.
    private var foreground: Color {
        guard !usesGlass || tintsGlass else { return .primary }
        switch filter.tint {
        case .accent: return .white
        case let .palette(index): return LabelToken.glyph(for: index)
        }
    }

    /// The same chip with untinted glass, for snapshot tests.
    func untintedForSnapshot() -> Self {
        var copy = self
        copy.tintsGlass = false
        return copy
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ChatListFilterChip(
            filter: ChatListActiveFilter(title: "Unread", systemImage: "circlebadge", tint: .accent),
            usesGlass: true,
            clear: {}
        )
        ChatListFilterChip(
            filter: ChatListActiveFilter(title: "Work · Unread", systemImage: "briefcase", tint: .palette(6)),
            usesGlass: true,
            clear: {}
        )
        ChatListFilterChip(
            filter: ChatListActiveFilter(title: "DevObsessed", systemImage: "square.grid.2x2", tint: .palette(3)),
            usesGlass: false,
            clear: {}
        )
    }
    .padding()
}
