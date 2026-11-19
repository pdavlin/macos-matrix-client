import Models
import SwiftUI
import Tokens

/// The thread chip under a thread root in the main column (MATRIX-183): a
/// button that reads "N replies" with a trailing chevron, and the latest
/// reply on a second line. A click opens the thread panel.
public struct MessageThreadSummary: View {
    let summary: ThreadSummary
    let action: () -> Void

    public init(summary: ThreadSummary, action: @escaping () -> Void) {
        self.summary = summary
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: ThreadToken.chipSpacing) {
                HStack(spacing: ThreadToken.chipChevronSpacing) {
                    Text(ThreadReplyCount.label(Int(summary.numReplies())))
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }

                if let description = summary.description {
                    Text(description.formatAsMarkdown)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DensityToken.threadSummaryPadding)
            .background(
                RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                    .fill(Color.primary.opacity(BubbleToken.threadSummaryBackgroundOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                    .strokeBorder(Color(PlatformColor.separatorColor), lineWidth: ThreadToken.chipBorderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: BubbleToken.cornerRadius))
        }
        .buttonStyle(.plain)
        .help("Open Thread")
    }
}

#Preview {
    MessageThreadSummary(summary: MockThreadSummary()) {}
        .padding()
}
