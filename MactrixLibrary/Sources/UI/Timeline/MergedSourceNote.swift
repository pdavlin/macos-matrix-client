import Models
import SwiftUI
import Tokens

/// The source note of a merged timeline (MATRIX-142): a small centered label
/// above the first message of a run from another member room, for example
/// "Slack • DevObsessed", with the chat list's network badge in front of it.
///
/// The view holds no rule: Phase B picks the title and the detail for each
/// member room. Beeper's rule is the network name, plus " • " and an
/// identifier when two or more members share that network.
///
/// The row height is fixed at `MergedSourceNoteToken.height` at every width.
/// The label is one line and truncates, so the pre-measured height is always
/// right. It is opaque decoration on the timeline: no glass (hard rule 2).
public struct MergedSourceNote: View {
    let network: ChatListNetwork?
    let title: String
    let detail: String?
    let account: ChatAccount?

    @Environment(\.chatBadgeImageLoader) private var badgeImageLoader

    /// - Parameters:
    ///   - network: the bridged network of the member room. Nil shows no
    ///     badge.
    ///   - title: the first part of the label, usually the network's display
    ///     name, or the room's name when the network is not known.
    ///   - detail: the part after " • " that tells two rooms of one network
    ///     apart, or nil for no second part.
    ///   - account: the member room's account. Its icon replaces the
    ///     network letter on the badge (MATRIX-148).
    public init(network: ChatListNetwork?, title: String, detail: String? = nil, account: ChatAccount? = nil) {
        self.network = network
        self.title = title
        self.detail = detail
        self.account = account
    }

    public var body: some View {
        HStack(spacing: MergedSourceNoteToken.badgeSpacing) {
            if ChatBadge(network: network, account: account).isVisible {
                ChatListAccountBadge(
                    network: network,
                    account: account,
                    size: MergedSourceNoteToken.badgeSize,
                    imageLoader: badgeImageLoader
                )
                .accessibilityHidden(true)
            }
            label
                .font(.system(size: MergedSourceNoteToken.fontSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, DensityToken.dividerHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(height: MergedSourceNoteToken.height)
        .accessibilityElement(children: .combine)
    }

    private var label: Text {
        if let detail {
            Text(
                "\(title) • \(detail)",
                comment: "A merged-chat source note: a network name, then the account or chat that tells two rooms of that network apart."
            )
        } else {
            Text(verbatim: title)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        MergedSourceNote(network: .slack, title: "Slack", detail: "DevObsessed")
        MergedSourceNote(network: .googleChat, title: "Google Chat")
        MergedSourceNote(network: nil, title: "Seth")
    }
    .frame(width: 400)
    .background(Color(PlatformColor.controlBackgroundColor))
}
