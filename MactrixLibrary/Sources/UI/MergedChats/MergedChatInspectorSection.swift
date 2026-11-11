import Models
import SwiftUI

/// The merged-chat part of a room's inspector (MATRIX-141 Phase B).
///
/// - A one-to-one chat in no merged chat offers "Merge with…".
/// - A member room says which merged chat holds it and offers "Edit Merged
///   Chat…" and "Unmerge".
/// - Any other room shows nothing.
///
/// The status comes from `RoomMergeStatus.of(roomId:isDirect:document:)`. The
/// view is plain content; the inspector puts it in a list section.
public struct MergedChatInspectorSection: View {
    let status: RoomMergeStatus
    let isEditable: Bool
    let onMerge: () -> Void
    let onEdit: () -> Void
    let onUnmerge: () -> Void

    /// - Parameters:
    ///   - status: the room's merge status.
    ///   - isEditable: the merged chats can be written
    ///     (`MergedChatsModel.isEditable`). The buttons are disabled when not.
    ///   - onMerge: "Merge with…": open the Merge Chats sheet for this room.
    ///   - onEdit: "Edit Merged Chat…": open the sheet for the merged chat.
    ///   - onUnmerge: "Unmerge": remove the merged chat. No confirmation, because an
    ///     unmerge is undone by merging again.
    public init(
        status: RoomMergeStatus,
        isEditable: Bool,
        onMerge: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onUnmerge: @escaping () -> Void
    ) {
        self.status = status
        self.isEditable = isEditable
        self.onMerge = onMerge
        self.onEdit = onEdit
        self.onUnmerge = onUnmerge
    }

    public var body: some View {
        switch status {
        case .unavailable:
            EmptyView()
        case .mergeable:
            VStack(alignment: .leading, spacing: 8) {
                Text("Show this chat and other chats with the same person as one chat.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Merge with…", action: onMerge)
                    .disabled(!isEditable)
            }
        case let .member(merge):
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Merged into \(merge.name)")
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "rectangle.stack")
                }
                HStack(spacing: 8) {
                    Button("Edit Merged Chat…", action: onEdit)
                    Button("Unmerge", action: onUnmerge)
                }
                .disabled(!isEditable)
            }
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 24) {
        MergedChatInspectorSection(status: .mergeable, isEditable: true, onMerge: {}, onEdit: {}, onUnmerge: {})
        MergedChatInspectorSection(
            status: .member(of: MergedChat(id: "m", name: "Seth", rooms: ["!a", "!b"])),
            isEditable: true,
            onMerge: {},
            onEdit: {},
            onUnmerge: {}
        )
    }
    .padding()
    .frame(width: 260)
}
