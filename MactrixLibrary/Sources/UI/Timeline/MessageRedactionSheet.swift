import SwiftUI

/// The confirmation before a message is deleted (redacted) for everyone
/// (MATRIX-110, M2-B3).
///
/// It asks once, with an optional reason. Cancel is the default button, so
/// Return never deletes by accident: only a click on Delete does. Escape also
/// cancels. The sheet makes no SDK call; the caller gets the typed reason and
/// sends the redaction.
///
/// Usage:
/// ```swift
/// .sheet(item: $timeline.pendingRedaction) { request in
///     MessageRedactionSheet(isOwn: request.isOwn, onDelete: { reason in ... }, onCancel: { ... })
/// }
/// ```
public struct MessageRedactionSheet: View {
    let isOwn: Bool
    let onDelete: (String) -> Void
    let onCancel: () -> Void

    @State private var reason = ""

    /// - Parameters:
    ///   - isOwn: Whether the signed-in account sent the message. Another
    ///     person's message gets a moderator note.
    ///   - onDelete: Runs with the typed reason, which can be empty.
    ///   - onCancel: Runs when the person cancels.
    public init(isOwn: Bool, onDelete: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.isOwn = isOwn
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    private var explanation: LocalizedStringKey {
        isOwn
            ? "The message is removed for everyone in the room. Bridged chats remove it where they can."
            : "You delete another person's message as a moderator. The message is removed for everyone in the room."
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Delete this message?", systemImage: "trash")
                .font(.title2)
                .bold()

            Text(explanation)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Reason (optional)", text: $reason)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Delete", role: .destructive) { onDelete(reason) }
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .sheetContentWidth(420)
        .cancelsOnExitCommand(onCancel)
    }
}

extension View {
    /// Escape runs `action` on macOS. iOS has no Escape key path for a sheet,
    /// and the Cancel button covers it. The forward confirmation uses it too
    /// (MATRIX-112).
    func cancelsOnExitCommand(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
            onExitCommand(perform: action)
        #else
            self
        #endif
    }
}
