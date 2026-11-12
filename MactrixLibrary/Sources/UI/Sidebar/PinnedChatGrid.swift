import SwiftUI
import Tokens

/// The grid of pinned favourites above the chat list (MATRIX-150).
///
/// A pure layout view, so the package's snapshot tests can render it: the
/// sidebar passes the items and builds each tile.
///
/// The grid is on the chat list's layout. It takes the width of a list row's
/// content and shares it equally between as many columns as fit. The tiles
/// touch, and each pads its content by `ChatListToken.pinnedTilePadding`, so
/// the gap between two tiles' contents is `pinnedGridGap` in both directions.
/// The grid reaches `pinnedGridGutterOutset` into each gutter: the first
/// column's avatar starts at the rows' avatar edge and the last column's
/// content ends at the rows' trailing edge. A last row that is not full
/// starts at the leading edge.
public struct PinnedChatGrid<Data: RandomAccessCollection, Tile: View>: View where Data.Element: Identifiable {
    let items: Data
    let tile: (Data.Element) -> Tile

    public init(_ items: Data, @ViewBuilder tile: @escaping (Data.Element) -> Tile) {
        self.items = items
        self.tile = tile
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: ChatListToken.pinnedTileMinWidth), spacing: 0, alignment: .topLeading)]
    }

    public var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                tile(item)
            }
        }
        .padding(.horizontal, -ChatListToken.pinnedGridGutterOutset)
    }
}
