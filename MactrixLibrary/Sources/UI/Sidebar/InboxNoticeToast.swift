import Models
import SwiftUI

/// The short note at the foot of the chat list after an inbox action, with
/// its Undo button (MATRIX-206): "Archived Alice   Undo".
///
/// It floats over the list on a material, not on glass: the list under it
/// scrolls (CLAUDE.md hard rule 2).
public struct InboxNoticeToast: View {
    let message: String
    let undo: () -> Void

    public init(message: String, undo: @escaping () -> Void) {
        self.message = message
        self.undo = undo
    }

    public var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            Button("Undo", action: undo)
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    InboxNoticeToast(message: "Archived Alice") {}
        .padding()
        .frame(width: 320)
}
