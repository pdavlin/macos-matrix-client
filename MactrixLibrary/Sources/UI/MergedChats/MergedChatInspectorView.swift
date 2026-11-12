import Models
import SwiftUI
import Tokens

/// The inspector of a merged chat (MATRIX-149): its name, its member chats,
/// and "Edit Merged Chat…".
///
/// Each member chat shows its avatar, its title, and the line that tells it
/// from the other members ("Slack • DevObsessed"), as the Merge Chats sheet
/// shows it. The view is static: the host gives it the rows and opens the
/// sheet.
///
/// ```swift
/// MergedChatInspectorView(
///     mergedRow: mergedRow,
///     members: members,
///     memberDetails: ["!a": "Slack • DevObsessed"],
///     imageLoader: client,
///     isEditable: true,
///     onEdit: { windowState.mergeEditor = .edit(mergedChatId: id) }
/// )
/// ```
public struct MergedChatInspectorView: View {
    let mergedRow: ChatListRowModel
    let members: [ChatListRowModel]
    let memberDetails: [String: String]
    let imageLoader: ImageLoader?
    let isEditable: Bool
    let onEdit: () -> Void

    /// - Parameters:
    ///   - mergedRow: the merged chat's own row: its name, avatar, and
    ///     network badges (`ChatListMerging.entry(for:members:)`).
    ///   - members: the member chats' rows, in member order.
    ///   - memberDetails: what tells each member chat apart, by room ID
    ///     (`MergedMemberIdentity.detail`). A chat without an entry shows
    ///     its network.
    ///   - imageLoader: loads avatar images; nil draws initials.
    ///   - isEditable: the merged chats can be written
    ///     (`MergedChatsModel.isEditable`). The button is disabled when not.
    ///   - onEdit: "Edit Merged Chat…": open the Merge Chats sheet.
    public init(
        mergedRow: ChatListRowModel,
        members: [ChatListRowModel],
        memberDetails: [String: String] = [:],
        imageLoader: ImageLoader?,
        isEditable: Bool,
        onEdit: @escaping () -> Void
    ) {
        self.mergedRow = mergedRow
        self.members = members
        self.memberDetails = memberDetails
        self.imageLoader = imageLoader
        self.isEditable = isEditable
        self.onEdit = onEdit
    }

    public var body: some View {
        let labels = MergedChatDraft.memberLabels(for: members, details: memberDetails)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                VStack(alignment: .leading, spacing: 6) {
                    Text("Chats (\(members.count))")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(zip(members, labels)), id: \.0.id) { member, label in
                            memberRow(member, label: label)
                            if member.id != members.last?.id {
                                Divider()
                            }
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
                }

                Button("Edit Merged Chat…", action: onEdit)
                    .disabled(!isEditable)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            ChatListAvatar(model: mergedRow, size: MergedChatToken.inspectorAvatarSize, imageLoader: imageLoader)
            Text(verbatim: mergedRow.title)
                .font(.title)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .textSelection(.enabled)
            Text("Merged chat")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func memberRow(_ member: ChatListRowModel, label: String) -> some View {
        // The detail line names the network, so the small avatar draws no
        // badge, as in the Merge Chats sheet.
        var avatarModel = member
        avatarModel.network = nil
        avatarModel.account = nil
        avatarModel.additionalNetworks = []
        return HStack(spacing: 8) {
            ChatListAvatar(model: avatarModel, size: MergedChatToken.sheetMemberAvatarSize, imageLoader: imageLoader)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: member.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = memberDetails[member.id] ?? member.network?.displayName {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
    return MergedChatInspectorView(
        mergedRow: merged,
        members: [
            ChatListRowModel(id: "!a", title: "Seth Redacted", isDirect: true, network: .slack),
            ChatListRowModel(id: "!b", title: "Seth R.", isDirect: true, network: .googleChat),
        ],
        memberDetails: ["!a": "Slack • DevObsessed"],
        imageLoader: nil,
        isEditable: true,
        onEdit: {}
    )
    .frame(width: 260, height: 420)
}
