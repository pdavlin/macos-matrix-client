import Foundation

/// What the reaction picker's grid shows for a query, and how the arrow keys
/// move through it (MATRIX-111, M2-B4, D-3).
///
/// An empty query shows the whole catalog, one section for each category. A
/// query shows one untitled section of search results, best match first.
/// The keyboard selection is an index into `entries`, the sections joined in
/// order. With no explicit selection the first entry is selected, so Return
/// picks the first match.
///
/// Usage:
/// ```swift
/// let content = EmojiPickerContent(catalog: catalog, query: "thumbs")
/// let next = content.index(after: .down, from: 0, columns: 9)
/// ```
public struct EmojiPickerContent: Equatable, Sendable {
    /// One block of the grid.
    public struct Section: Equatable, Sendable, Identifiable {
        /// The category name, or nil for search results.
        public let title: String?
        public let entries: [EmojiCatalog.Entry]
        /// The index of the section's first entry in `EmojiPickerContent.entries`.
        public let startIndex: Int

        public var id: Int {
            startIndex
        }
    }

    /// An arrow key.
    public enum Move: Equatable, Sendable {
        case left
        case right
        case up
        case down
    }

    public let sections: [Section]
    /// Every entry the grid shows, in display order.
    public let entries: [EmojiCatalog.Entry]
    /// Whether the content holds search results, not the whole catalog.
    public let isSearch: Bool

    /// - Parameters:
    ///   - catalog: All emoji.
    ///   - query: The search text. Blank text shows the whole catalog.
    public init(catalog: EmojiCatalog, query: String) {
        let isSearch = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        var sections: [Section] = []
        var start = 0
        if isSearch {
            let results = catalog.search(query)
            if !results.isEmpty {
                sections.append(Section(title: nil, entries: results, startIndex: 0))
            }
        } else {
            for category in catalog.categories {
                sections.append(Section(title: category.name, entries: category.entries, startIndex: start))
                start += category.entries.count
            }
        }
        self.sections = sections
        self.entries = sections.flatMap(\.entries)
        self.isSearch = isSearch
    }

    /// The index Return acts on: `selection` if it is still in range, else
    /// the first entry. Nil when the grid is empty.
    public func effectiveSelection(_ selection: Int?) -> Int? {
        if let selection, entries.indices.contains(selection) {
            return selection
        }
        return entries.isEmpty ? nil : 0
    }

    /// The index an arrow key moves to.
    ///
    /// Left and right step one entry and cross section ends. Up and down move
    /// to the same column of the row above or below, as the grid draws it:
    /// each section starts a new row, so the row above can be shorter, and
    /// the column then clamps to its last entry. Moves stop at the first and
    /// last entry.
    ///
    /// - Parameters:
    ///   - move: The arrow key.
    ///   - index: The current selection.
    ///   - columns: The grid's column count, at least 1.
    /// - Returns: The new selection, or nil when the grid is empty.
    public func index(after move: Move, from index: Int, columns: Int) -> Int? {
        guard !entries.isEmpty else { return nil }
        let current = min(max(index, 0), entries.count - 1)
        switch move {
        case .left:
            return max(current - 1, 0)
        case .right:
            return min(current + 1, entries.count - 1)
        case .up, .down:
            let rows = rowRanges(columns: max(columns, 1))
            guard let row = rows.firstIndex(where: { $0.contains(current) }) else { return current }
            let target = move == .up ? row - 1 : row + 1
            guard rows.indices.contains(target) else { return current }
            let column = current - rows[row].lowerBound
            return min(rows[target].lowerBound + column, rows[target].upperBound - 1)
        }
    }

    /// The grid rows as ranges of entry indices.
    func rowRanges(columns: Int) -> [Range<Int>] {
        sections.flatMap { section in
            stride(from: 0, to: section.entries.count, by: columns).map { offset in
                let lower = section.startIndex + offset
                return lower ..< min(lower + columns, section.startIndex + section.entries.count)
            }
        }
    }
}
