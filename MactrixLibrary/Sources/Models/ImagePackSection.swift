import Foundation

/// One image pack as a section of the reaction picker's grid (MATRIX-155).
///
/// The grid's cells are `EmojiCatalog.Entry` values, so the section holds one
/// entry for each emoji of the pack: `value` is the `mxc://` URI that a pick
/// sends, and `name` is the shortcode. The entries are made once, when the
/// picker opens, not on each redraw.
///
/// Usage:
/// ```swift
/// let sections = packs.map(ImagePackSection.init)
/// let content = EmojiPickerContent(catalog: catalog, packs: sections, query: "")
/// ```
public struct ImagePackSection: Equatable, Sendable {
    /// The section title used when the pack has no name.
    public static let untitled = "Custom Emoji"

    /// The pack's display name. The store sets the workspace name on a pack
    /// that has no name of its own.
    public let title: String
    /// One entry for each emoji, in the pack's order.
    public let entries: [EmojiCatalog.Entry]

    private let pack: ImagePack

    public init(pack: ImagePack) {
        let title = pack.displayName ?? Self.untitled
        self.pack = pack
        self.title = title
        self.entries = pack.emoji.map { emoji in
            EmojiCatalog.Entry(
                id: "pack:\(pack.key):\(emoji.shortcode)",
                value: emoji.url,
                name: emoji.shortcode,
                group: title,
                subgroup: ""
            )
        }
    }

    /// The entries that `ImagePack.search(_:)` finds, in its order.
    public func search(_ query: String) -> [EmojiCatalog.Entry] {
        pack.searchIndices(query).map { entries[$0] }
    }
}
