import Models
import SwiftUI

/// A chosen person in the To: field: avatar and name in a capsule, with a
/// remove button. Sizes follow Beeper's pill (rounded 20, 2/8 padding).
struct NewChatPill: View {
    let person: NewChatPerson
    let imageLoader: ImageLoader?
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            AvatarImage(userProfile: person, imageLoader: imageLoader)
                .frame(width: 16, height: 16)
                .clipShape(Circle())
            Text(person.label)
                .font(.system(size: 13))
                .lineLimit(1)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(person.label)")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .help(person.userId)
    }
}

/// The highlight shared by action rows and person rows: rounded 6, filled when
/// the row is under the pointer or the keyboard selection.
private struct NewChatRowBackground: ViewModifier {
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? Color.primary.opacity(0.08) : Color.clear)
            )
    }
}

/// A leading action ("New Group", "Join a Matrix room"): icon and a semibold
/// 13 pt label in a 36 pt row.
struct NewChatActionRow: View {
    let title: String
    let systemImage: String
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.08)))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
        }
        .frame(height: 36)
        .modifier(NewChatRowBackground(isHighlighted: isHighlighted))
    }
}

/// A person in the results: avatar, name, and the user ID when it differs
/// from the name.
struct NewChatPersonRow: View {
    let person: NewChatPerson
    let imageLoader: ImageLoader?
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            AvatarImage(userProfile: person, imageLoader: imageLoader)
                .frame(width: 24, height: 24)
                .clipShape(Circle())
            Text(person.label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if person.label != person.userId {
                Text(person.userId)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: 36)
        .modifier(NewChatRowBackground(isHighlighted: isHighlighted))
    }
}

/// The primary footer button with Beeper's "⏎" hint.
struct NewChatPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("⏎")
                    .opacity(0.7)
            }
            .padding(.horizontal, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
    }
}

/// The confirm shown before a group is created. Encryption cannot be turned
/// off later, so the choice is made here, defaulting to on.
struct NewChatEncryptionConfirm: View {
    @Binding var isEncrypted: Bool
    let isBusy: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Room encryption")
                .font(.system(size: 15, weight: .semibold))

            Toggle("Encrypted", isOn: $isEncrypted)
                .toggleStyle(.switch)

            Text(isEncrypted
                ? "People invited later cannot see earlier messages."
                : "People invited later can see earlier messages.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isBusy ? "Starting..." : "Start group chat", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy)
            }
        }
        .padding(20)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        )
    }
}

/// Lays pills out left to right, wrapping to a new line when a row is full.
struct NewChatFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let frames = frames(for: subviews, maxWidth: proposal.width ?? .infinity)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let frames = frames(for: subviews, maxWidth: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(for subviews: Subviews, maxWidth: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return frames
    }
}
