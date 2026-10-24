import Models
import SwiftUI
import Tokens

/// The Create/Edit Label sheet (MATRIX-77), after Beeper's.
///
/// A title field and the icon and color picker, an explainer, then a
/// searchable checklist of chats: the chats the label starts with under
/// "Selected", every other chat under "Chats". The sections are fixed when
/// the sheet opens, so a checkbox does not jump between them while the user
/// works. Save needs a name, at least one chat, and a change.
public struct LabelEditSheet: View {
    let isNew: Bool
    let original: ChatLabelDraft
    let chats: [ChatListRowModel]
    let imageLoader: ImageLoader?
    let onCancel: () -> Void
    let onSave: (ChatLabelDraft) -> Void

    @State private var draft: ChatLabelDraft
    @State private var query = ""
    @FocusState private var nameFocused: Bool

    /// - Parameters:
    ///   - draft: the starting state: an empty draft (or one with a
    ///     preselected chat) for a new label, `ChatLabelDraft(label:)` to edit.
    ///   - chats: every chat the user can pick, in display order.
    public init(
        isNew: Bool,
        draft: ChatLabelDraft,
        chats: [ChatListRowModel],
        imageLoader: ImageLoader?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ChatLabelDraft) -> Void
    ) {
        self.isNew = isNew
        self.original = draft
        self.chats = chats
        self.imageLoader = imageLoader
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    /// The starting chats, in label order. A room the chat list does not
    /// hold (left, or not loaded yet) still shows, by ID, so it can be
    /// unchecked.
    private var selectedSection: [ChatListRowModel] {
        let byId = Dictionary(chats.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return original.rooms.map { byId[$0] ?? ChatListRowModel(id: $0, title: $0) }.filter(matches)
    }

    private var otherSection: [ChatListRowModel] {
        let initial = Set(original.rooms)
        return chats.filter { !initial.contains($0.id) && matches($0) }
    }

    private func matches(_ chat: ChatListRowModel) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || chat.title.localizedCaseInsensitiveContains(trimmed)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New Label" : "Edit Label")
                .font(.headline)

            HStack(spacing: 8) {
                LabelIconColorPicker(name: draft.name, colorIndex: $draft.colorIndex, icon: $draft.icon)
                TextField("Label name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
            }

            Text("Choose a title, icon, and/or color to customize your label. This is how it will appear throughout the app.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            chatPicker

            HStack {
                Text(draft.rooms.count == 1 ? "1 chat selected" : "\(draft.rooms.count) chats selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    var saved = draft
                    saved.name = draft.trimmedName
                    onSave(saved)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.canSave(comparedTo: original))
            }
        }
        .padding(20)
        .frame(width: LabelToken.sheetWidth)
        .onAppear {
            nameFocused = isNew
        }
    }

    private var chatPicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search chats", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)

            Divider()

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    let selected = selectedSection
                    if !selected.isEmpty {
                        section("Selected", chats: selected)
                    }
                    section("Chats", chats: otherSection)
                }
            }
            .frame(height: LabelToken.sheetChatListHeight)
        }
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func section(_ title: String, chats: [ChatListRowModel]) -> some View {
        Section {
            ForEach(chats) { chat in
                chatRow(chat)
            }
        } header: {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background)
        }
    }

    private func chatRow(_ chat: ChatListRowModel) -> some View {
        let isSelected = draft.isSelected(chat.id)
        // The network badge is sized for the chat list's 46 pt avatar and
        // would cover this one.
        var avatarModel = chat
        avatarModel.network = nil
        return Button {
            draft.toggle(chat.id)
        } label: {
            HStack(spacing: 8) {
                ChatListAvatar(model: avatarModel, size: LabelToken.sheetAvatarSize, imageLoader: imageLoader)
                Text(chat.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chat.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
