import Models
import SwiftUI
import Tokens

/// The mention autocomplete popup (MATRIX-105, D-6): the room members that
/// match the text after "@".
///
/// The view only draws the rows and reports a click. The composer owns the
/// state (`MentionAutocompleteState`) and the keyboard: arrow keys move the
/// selection, Return or Tab picks it, and Esc closes the popup.
public struct MentionSuggestionList: View {
    let suggestions: [MentionCandidate]
    let selectedIndex: Int
    let imageLoader: ImageLoader?
    let onPick: (MentionCandidate) -> Void

    /// - Parameters:
    ///   - suggestions: the rows, best match first.
    ///   - selectedIndex: the row that Return picks.
    ///   - imageLoader: loads member avatars. Nil shows the placeholders.
    ///   - onPick: called with the row the user clicks.
    public init(
        suggestions: [MentionCandidate],
        selectedIndex: Int,
        imageLoader: ImageLoader?,
        onPick: @escaping (MentionCandidate) -> Void
    ) {
        self.suggestions = suggestions
        self.selectedIndex = selectedIndex
        self.imageLoader = imageLoader
        self.onPick = onPick
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.userId) { index, candidate in
                Button {
                    onPick(candidate)
                } label: {
                    MentionSuggestionRow(
                        candidate: candidate,
                        isSelected: index == selectedIndex,
                        imageLoader: imageLoader
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Mention suggestions"))
    }
}

/// One popup row: avatar, display name, and user id.
struct MentionSuggestionRow: View {
    let candidate: MentionCandidate
    let isSelected: Bool
    let imageLoader: ImageLoader?

    var body: some View {
        HStack(spacing: 8) {
            AvatarImage(userProfile: candidate, imageLoader: imageLoader)
                .frame(width: MentionToken.rowAvatarSize, height: MentionToken.rowAvatarSize)
                .clipShape(.circle)
            Text(candidate.displayName ?? candidate.userId)
                .lineLimit(1)
            Text(candidate.userId)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .background(
            RoundedRectangle(cornerRadius: MentionToken.rowCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(MentionToken.selectedRowOpacity) : Color.clear)
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    MentionSuggestionList(
        suggestions: [
            MentionCandidate(userId: "@alice:example.org", displayName: "Alice", avatarUrl: nil),
            MentionCandidate(userId: "@alfred:example.org", displayName: "Alfred Pennyworth", avatarUrl: nil),
        ],
        selectedIndex: 0,
        imageLoader: nil,
        onPick: { _ in }
    )
    .frame(width: 360)
}
