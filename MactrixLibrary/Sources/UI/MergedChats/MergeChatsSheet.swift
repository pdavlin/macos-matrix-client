import Models
import SwiftUI
import Tokens

/// The Merge Chats sheet (MATRIX-141, contract §4 M2.5).
///
/// Shows the member chats with a remove button each and an "Add Chat…"
/// button, the merged chat's name, an avatar picker and a default-chat picker
/// among the members, then Cancel and Merge. In edit mode the confirm button
/// reads Save and an Unmerge button sits on the leading edge.
///
/// The host owns the draft through a binding, so it can add a chat while the
/// sheet is open (the "Add Chat…" closure opens the quick switcher in
/// Phase B). The sheet holds no Core type: the member rows are plain
/// `ChatListRowModel` values and every action is a closure.
public struct MergeChatsSheet: View {
    /// Whether the sheet makes a new merged chat or edits one.
    public enum Mode: Equatable, Sendable {
        case create
        case edit
    }

    let mode: Mode
    @Binding var draft: MergedChatDraft
    let chats: [ChatListRowModel]
    let imageLoader: ImageLoader?
    let onAddChat: () -> Void
    let onCancel: () -> Void
    let onSubmit: (MergedChatDraft) -> Void
    let onUnmerge: () -> Void

    /// - Parameters:
    ///   - mode: create or edit.
    ///   - draft: the sheet's state. `MergedChatDraft(chats:)` for a new
    ///     merged chat, `MergedChatDraft(merge:)` to edit one.
    ///   - chats: the rows of the draft's chats, and any other chats the host
    ///     knows. A member without a row shows by its room ID.
    ///   - imageLoader: loads avatar images; nil draws initials.
    ///   - onAddChat: "Add Chat…": the host picks a chat and adds it to the
    ///     draft (with its row in `chats`).
    ///   - onCancel: Cancel or Escape.
    ///   - onSubmit: Merge (create) or Save (edit), with the draft. Enabled
    ///     only when `MergedChatDraft.canSubmit` holds.
    ///   - onUnmerge: Unmerge, shown in edit mode only.
    public init(
        mode: Mode,
        draft: Binding<MergedChatDraft>,
        chats: [ChatListRowModel],
        imageLoader: ImageLoader?,
        onAddChat: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (MergedChatDraft) -> Void,
        onUnmerge: @escaping () -> Void = {}
    ) {
        self.mode = mode
        _draft = draft
        self.chats = chats
        self.imageLoader = imageLoader
        self.onAddChat = onAddChat
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        self.onUnmerge = onUnmerge
    }

    /// The draft's chats as rows, in draft order.
    private var members: [ChatListRowModel] {
        let byId = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return draft.rooms.map { byId[$0] ?? ChatListRowModel(id: $0, title: $0) }
    }

    public var body: some View {
        let members = members
        let labels = MergedChatDraft.memberLabels(for: members)

        VStack(alignment: .leading, spacing: 14) {
            Text(mode == .create ? "Merge Chats" : "Edit Merged Chat")
                .font(.headline)

            Text("Show these chats with the same person as one chat. Each chat keeps its own messages.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Name", text: $draft.name)
                .textFieldStyle(.roundedBorder)

            memberList(members)

            if !members.isEmpty {
                avatarPicker(members, labels: labels)
                defaultChatPicker(members, labels: labels)
            }

            footer
        }
        .padding(20)
        .frame(width: MergedChatToken.sheetWidth)
    }

    // MARK: Members

    private func memberList(_ members: [ChatListRowModel]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(members) { member in
                memberRow(member)
                Divider()
            }
            Button(action: onAddChat) {
                Label("Add Chat…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func memberRow(_ member: ChatListRowModel) -> some View {
        // The network shows as text, so the small avatar draws no badge.
        var avatarModel = member
        avatarModel.network = nil
        avatarModel.additionalNetworks = []
        return HStack(spacing: 8) {
            ChatListAvatar(model: avatarModel, size: MergedChatToken.sheetMemberAvatarSize, imageLoader: imageLoader)
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
            Spacer(minLength: 8)
            Button {
                draft.remove(member.id)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from merged chat")
            .accessibilityLabel(Text("Remove \(member.title)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: Pickers

    private func avatarPicker(_ members: [ChatListRowModel], labels: [String]) -> some View {
        let hasImage = Set(members.filter(\.hasAvatarImage).map(\.id))
        let chosen = draft.effectiveAvatarRoom { hasImage.contains($0) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Avatar")
                .font(.callout.weight(.semibold))
            HStack(spacing: 10) {
                ForEach(Array(zip(members, labels)), id: \.0.id) { member, label in
                    avatarChoice(member, label: label, isChosen: member.id == chosen)
                }
            }
        }
    }

    private func avatarChoice(_ member: ChatListRowModel, label: String, isChosen: Bool) -> some View {
        var avatarModel = member
        avatarModel.network = nil
        avatarModel.additionalNetworks = []
        let ringSize = MergedChatToken.sheetPickerAvatarSize + 2 * MergedChatToken.sheetPickerRingInset
        return Button {
            draft.avatarRoom = member.id
        } label: {
            ChatListAvatar(model: avatarModel, size: MergedChatToken.sheetPickerAvatarSize, imageLoader: imageLoader)
                .padding(MergedChatToken.sheetPickerRingInset)
                .overlay {
                    Circle()
                        .strokeBorder(
                            isChosen ? Color.accentColor : Color.clear,
                            lineWidth: MergedChatToken.sheetPickerRingWidth
                        )
                        .frame(width: ringSize, height: ringSize)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    private func defaultChatPicker(_ members: [ChatListRowModel], labels: [String]) -> some View {
        let selection = Binding<String>(
            get: { draft.effectiveDefaultRoom ?? "" },
            set: { draft.defaultRoom = $0 }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Picker("Default chat", selection: selection) {
                ForEach(Array(zip(members, labels)), id: \.0.id) { member, label in
                    Text(verbatim: label).tag(member.id)
                }
            }
            .pickerStyle(.menu)
            Text("New messages go here when your last message is more than 30 minutes old.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if mode == .edit {
                Button("Unmerge", role: .destructive, action: onUnmerge)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button(mode == .create ? "Merge" : "Save") {
                var submitted = draft
                submitted.name = draft.trimmedName
                onSubmit(submitted)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!draft.canSubmit)
        }
    }
}

#Preview {
    @Previewable @State var draft = MergedChatDraft(name: "Seth", rooms: ["!a", "!b"])
    MergeChatsSheet(
        mode: .edit,
        draft: $draft,
        chats: [
            ChatListRowModel(id: "!a", title: "Seth Redacted", isDirect: true, network: .slack),
            ChatListRowModel(id: "!b", title: "Seth Redacted", isDirect: true, network: .slack),
        ],
        imageLoader: nil,
        onAddChat: {},
        onCancel: {},
        onSubmit: { _ in }
    )
}
