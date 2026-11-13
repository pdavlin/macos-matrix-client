import Models
import SwiftUI

/// What the reaction picker draws for one emoji: the character of a Unicode
/// emoji, or the image of a custom emoji (MATRIX-155).
///
/// The image is a square with the side of the font size, so a custom emoji
/// takes the same space in a cell as a Unicode emoji and the cell does not
/// change when the image arrives. The image loads through `AvatarImage` and
/// the app's `ImageLoader`, which fills its square: an image that is not
/// square is cropped at the center. Until it loads, the square is a quiet
/// placeholder.
struct ReactionPickerGlyph: View {
    let entry: EmojiCatalog.Entry
    let fontSize: CGFloat
    let imageLoader: ImageLoader?

    var body: some View {
        if entry.isImage {
            AvatarImage(avatarUrl: entry.value, imageLoader: imageLoader) {
                Color.primary.opacity(0.08)
            }
            .frame(width: fontSize, height: fontSize)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        } else {
            Text(verbatim: entry.value)
                .font(.system(size: fontSize))
        }
    }
}
