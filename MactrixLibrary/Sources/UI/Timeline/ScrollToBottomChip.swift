import SwiftUI
import Tokens

/// Floating affordance that jumps the timeline back to the newest message.
///
/// Shown while the user is scrolled away from the bottom. When new messages
/// arrive in that state, the chip carries their count; the count clears when
/// the timeline returns to the bottom. The chip floats over the timeline but
/// is not scrollable content itself; it deliberately uses an opaque control
/// background, not `.glassEffect()`, per the glass rule.
public struct ScrollToBottomChip: View {
    let unseenCount: Int
    let action: () -> Void

    @Environment(\.timelineTypography) private var typography

    public init(unseenCount: Int, action: @escaping () -> Void) {
        self.unseenCount = unseenCount
        self.action = action
    }

    var countLabel: String? {
        guard unseenCount > 0 else { return nil }
        return unseenCount > 99 ? "99+" : "\(unseenCount)"
    }

    var accessibilityText: String {
        guard unseenCount > 0 else { return "Scroll to bottom" }
        return "Scroll to bottom, \(unseenCount) new \(unseenCount == 1 ? "message" : "messages")"
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DensityToken.scrollChipSpacing) {
                if let countLabel {
                    Text(countLabel)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                }
                Image(systemName: "chevron.down")
            }
            .font(.system(size: typography.footnote))
            .padding(DensityToken.scrollChipPadding)
            .background(
                Capsule()
                    .fill(Color(NSColor.controlBackgroundColor))
                    .stroke(Color(NSColor.separatorColor), lineWidth: BubbleToken.hoverBorderWidth)
                    .shadow(color: .black.opacity(BubbleToken.hoverShadowOpacity), radius: BubbleToken.hoverShadowRadius)
            )
        }
        .buttonStyle(.plain)
        .help("Scroll to bottom")
        .accessibilityLabel(accessibilityText)
    }
}

#Preview {
    VStack {
        ScrollToBottomChip(unseenCount: 0) {}
        ScrollToBottomChip(unseenCount: 3) {}
        ScrollToBottomChip(unseenCount: 250) {}
    }
    .padding()
}
