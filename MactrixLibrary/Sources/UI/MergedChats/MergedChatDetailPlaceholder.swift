import Models
import SwiftUI
import Tokens

/// The detail area of a selected merged chat until the merged timeline lands
/// (MATRIX-141 Phase B). The merged chat view of the next build replaces it.
///
/// It shows the merged chat's avatar with its network badges, its name, each
/// member chat with its own network badge and network name, and a note that
/// the merged timeline comes next. The background is opaque (hard rule 2: no
/// glass on content). The view holds no Core type: the rows are plain
/// `ChatListRowModel` values.
public struct MergedChatDetailPlaceholder: View {
    let mergedRow: ChatListRowModel
    let members: [ChatListRowModel]
    let imageLoader: ImageLoader?

    /// - Parameters:
    ///   - mergedRow: the merged chat's row (`MergedChatListEntry.row`): its
    ///     title, avatar, and badge networks.
    ///   - members: the member chats' rows, in the merged chat's order.
    ///   - imageLoader: loads avatar images; nil draws initials.
    public init(mergedRow: ChatListRowModel, members: [ChatListRowModel], imageLoader: ImageLoader?) {
        self.mergedRow = mergedRow
        self.members = members
        self.imageLoader = imageLoader
    }

    public var body: some View {
        let labels = MergedChatDraft.memberLabels(for: members)
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                ChatListAvatar(model: mergedRow, size: MergedChatToken.placeholderAvatarSize, imageLoader: imageLoader)
                Text(verbatim: mergedRow.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("Merged chat")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(zip(members, labels)), id: \.0.id) { member, label in
                    memberRow(member, label: label)
                    if member.id != members.last?.id {
                        Divider()
                    }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .frame(maxWidth: MergedChatToken.placeholderMaxWidth)

            Text("Merged timeline arrives in the next build")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(PlatformColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
    }

    private func memberRow(_ member: ChatListRowModel, label: String) -> some View {
        HStack(spacing: 10) {
            ChatListAvatar(model: member, size: MergedChatToken.placeholderMemberAvatarSize, imageLoader: imageLoader)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: member.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let network = member.network {
                    Text(verbatim: network.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: label))
    }
}

#Preview {
    var merged = ChatListRowModel(id: "m-seth", title: "Seth", isDirect: true, network: .slack)
    merged.additionalNetworks = [.googleChat]
    return MergedChatDetailPlaceholder(
        mergedRow: merged,
        members: [
            ChatListRowModel(id: "!a", title: "Seth Redacted", isDirect: true, network: .slack),
            ChatListRowModel(id: "!b", title: "Seth R.", isDirect: true, network: .googleChat),
        ],
        imageLoader: nil
    )
    .frame(width: 600, height: 500)
}
