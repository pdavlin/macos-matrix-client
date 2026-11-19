import Models
import SwiftUI
import Tokens

/// The "N replies" divider of the thread panel (MATRIX-183), right after
/// the thread root: secondary small semibold text, centered, with a hairline
/// on each side. It gives the root its rank without a new row style.
///
/// The row height is fixed at `ThreadToken.repliesDividerHeight` at every
/// width, so the row measurement skips it (`TimelineRow.fixedHeight`). It is
/// opaque decoration on the timeline: no glass (hard rule 2).
public struct ThreadRepliesDividerRow: View {
    let count: Int

    @Environment(\.displayScale) private var displayScale

    public init(count: Int) {
        self.count = count
    }

    private var hairline: some View {
        Rectangle()
            .fill(Color(PlatformColor.separatorColor))
            .frame(height: 1 / displayScale)
            .frame(maxWidth: .infinity)
    }

    public var body: some View {
        HStack(spacing: ThreadToken.repliesDividerSpacing) {
            hairline
            Text(ThreadReplyCount.label(count))
                .font(.system(size: ThreadToken.repliesDividerFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            hairline
        }
        .frame(maxWidth: .infinity)
        .frame(height: ThreadToken.repliesDividerHeight)
        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
    }
}

#Preview {
    ThreadRepliesDividerRow(count: 4)
        .frame(width: 400)
        .background(Color(PlatformColor.controlBackgroundColor))
}
