import Models
import SwiftUI

/// The card that a long press on a reaction chip shows on iOS (MATRIX-249):
/// the reaction key, large, over the people who posted it. The text is the
/// text of the Mac tooltip (MATRIX-166, MATRIX-259): every person, and the
/// shortcode of a custom emoji when the room's image packs know it.
///
/// It is the preview of the chip's context menu. The system draws the
/// preview on its own platter, out of the timeline, so the card has no
/// background of its own.
///
/// Usage:
/// ```swift
/// ReactionChipPeopleCard(key: "👍", text: "Ana, Ben and You", imageLoader: imageLoader)
/// ```
public struct ReactionChipPeopleCard: View {
    let key: String
    let text: String
    let imageLoader: ImageLoader?

    /// The point size of the key: a custom emoji image takes the box of an
    /// emoji in this size (`ReactionKeyImage`).
    static let keyFontSize: CGFloat = 40
    /// The widest card. A longer list of people wraps.
    static let maxWidth: CGFloat = 280
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 8

    /// - Parameters:
    ///   - key: The reaction key. An `mxc://` key draws its image.
    ///   - text: The people, from `ReactionSenderSummary.tooltip(emojiName:)`.
    ///   - imageLoader: Loads the image of an `mxc://` key.
    public init(key: String, text: String, imageLoader: ImageLoader?) {
        self.key = key
        self.text = text
        self.imageLoader = imageLoader
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            ReactionKeyLabel(key: key, imageLoader: imageLoader)
                .font(.system(size: Self.keyFontSize))
            Text(verbatim: text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Self.padding)
        .frame(maxWidth: Self.maxWidth, alignment: .leading)
    }
}

#if os(iOS)
    extension View {
        /// Gives a reaction chip its long-press menu on iOS (MATRIX-249): the
        /// people card as the preview, and one action that toggles the
        /// account's own reaction with the chip's key, as a tap does.
        ///
        /// A context menu, not a popover: a long press is the system gesture
        /// for a context menu, and the innermost context menu takes the long
        /// press, so the chip's menu does not compete with the message row's
        /// menu around it. A popover needs a gesture of its own that competes
        /// with that menu, and on iPhone it becomes a sheet.
        ///
        /// The Mac shows the same people in the chip's tooltip
        /// (`reactionChipToolTip(_:)`) and gets no menu: a right-click on a
        /// chip keeps the row's menu.
        func reactionChipPeopleMenu(
            card: ReactionChipPeopleCard,
            isOwn: Bool,
            toggle: @escaping @MainActor () -> Void
        ) -> some View {
            contextMenu {
                Button(
                    ReactionChipMenu.toggleTitle(isOwn: isOwn),
                    systemImage: ReactionChipMenu.toggleSystemImage(isOwn: isOwn),
                    action: toggle
                )
            } preview: {
                card
            }
        }
    }
#endif
