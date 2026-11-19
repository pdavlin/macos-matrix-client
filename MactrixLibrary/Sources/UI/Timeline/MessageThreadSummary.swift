import Models
import SwiftUI
import Tokens

/// The thread chip under a thread root in the main column (MATRIX-183): a
/// pill styled like a reaction chip, with up to three replier avatars,
/// "N replies", and a chevron, then the latest reply on the same line. A
/// click opens the thread panel.
///
/// The count rolls to a new value (MATRIX-193). Every change is a width
/// change: the pill's content is never shorter than an avatar, and the
/// latest reply is one line beside the pill, so neither an avatar nor the
/// latest reply changes the row height.
public struct MessageThreadSummary: View {
    let summary: ThreadSummary
    let imageLoader: ImageLoader?
    let action: () -> Void

    /// - Parameters:
    ///   - summary: the SDK's thread summary.
    ///   - imageLoader: loads the replier avatars. Nil draws the initials.
    ///   - action: opens the thread.
    public init(summary: ThreadSummary, imageLoader: ImageLoader? = nil, action: @escaping () -> Void) {
        self.summary = summary
        self.imageLoader = imageLoader
        self.action = action
    }

    public var body: some View {
        let count = Int(summary.numReplies())
        let repliers = Array(summary.repliers.prefix(ThreadToken.chipMaxAvatars))
        HStack(spacing: ThreadToken.chipLatestReplySpacing) {
            Button(action: action) {
                HStack(spacing: ThreadToken.chipContentSpacing) {
                    if !repliers.isEmpty {
                        ThreadReplierAvatars(repliers: repliers, imageLoader: imageLoader)
                    }
                    Text(ThreadReplyCount.label(count))
                        .fontWeight(.semibold)
                        .rollingCountText(Double(count))
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: ThreadToken.chipAvatarSize)
                .padding(.vertical, DensityToken.reactionPadding)
                .padding(.horizontal, DensityToken.reactionCountPadding)
            }
            .buttonStyle(ReactionChipButtonStyle(isOwn: false))
            // The pill never wraps or shrinks; the latest reply gives way.
            .fixedSize()
            .rollingCountAnimation(Double(count))
            .help("Open Thread")
            .accessibilityLabel("\(ThreadReplyCount.label(count)), open thread")

            if let description = summary.description {
                Text(description.formatAsMarkdown)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// The overlapping avatars of the people who replied, newest first.
private struct ThreadReplierAvatars: View {
    let repliers: [ThreadReplier]
    let imageLoader: ImageLoader?

    var body: some View {
        HStack(spacing: -ThreadToken.chipAvatarOverlap) {
            ForEach(repliers, id: \.userId) { replier in
                AvatarImage(userProfile: replier, imageLoader: imageLoader)
                    .frame(width: ThreadToken.chipAvatarSize, height: ThreadToken.chipAvatarSize)
                    .clipShape(Circle())
                    .background(
                        Circle().stroke(Color(PlatformColor.controlBackgroundColor), lineWidth: ThreadToken.chipAvatarRingWidth)
                    )
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    MessageThreadSummary(summary: MockThreadSummary()) {}
        .padding()
}
