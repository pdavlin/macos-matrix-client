import Models
import SwiftUI
import Tokens

/// The composer's custom emoji completion list (MATRIX-156): the emoji of
/// the chat's image packs that match the text after ":".
///
/// The view only draws the rows and reports a click, as
/// `MentionSuggestionList` does. The composer owns the state
/// (`EmojiAutocompleteState`) and the keyboard. The list sits in the composer
/// surface and adds no material of its own.
public struct EmojiSuggestionList: View {
    let suggestions: [ImagePackEmoji]
    let selectedIndex: Int
    let imageLoader: ImageLoader?
    let onPick: (ImagePackEmoji) -> Void

    /// - Parameters:
    ///   - suggestions: the rows, best match first.
    ///   - selectedIndex: the row that Return picks.
    ///   - imageLoader: loads the emoji images. Nil shows the generic glyph.
    ///   - onPick: called with the row the user clicks.
    public init(
        suggestions: [ImagePackEmoji],
        selectedIndex: Int,
        imageLoader: ImageLoader?,
        onPick: @escaping (ImagePackEmoji) -> Void
    ) {
        self.suggestions = suggestions
        self.selectedIndex = selectedIndex
        self.imageLoader = imageLoader
        self.onPick = onPick
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.element.shortcode) { index, emoji in
                Button {
                    onPick(emoji)
                } label: {
                    EmojiSuggestionRow(emoji: emoji, isSelected: index == selectedIndex, imageLoader: imageLoader)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Emoji suggestions"))
    }
}

/// One list row: the image and the `:name:` token.
struct EmojiSuggestionRow: View {
    let emoji: ImagePackEmoji
    let isSelected: Bool
    let imageLoader: ImageLoader?

    var body: some View {
        HStack(spacing: 8) {
            ReactionKeyImage(mxcUrl: emoji.url, imageLoader: imageLoader)
                .accessibilityHidden(true)
            Text(verbatim: ":\(emoji.shortcode):")
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
    EmojiSuggestionList(
        suggestions: [
            ImagePackEmoji(shortcode: "party_parrot", url: "mxc://example.org/parrot"),
            ImagePackEmoji(shortcode: "parrot_wave", url: "mxc://example.org/wave"),
        ],
        selectedIndex: 0,
        imageLoader: nil,
        onPick: { _ in }
    )
    .frame(width: 360)
}
