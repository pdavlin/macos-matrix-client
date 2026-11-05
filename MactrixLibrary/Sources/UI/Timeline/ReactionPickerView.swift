import Foundation
import Models
import OSLog
import SwiftUI

public extension EmojiCatalog {
    /// The emoji list bundled in the UI target (`Resources/Emoji.txt`, Emoji
    /// 15.1). Parsed once, on first use. If the file is missing the catalog
    /// is empty and the picker shows only the recent emoji.
    static let bundled: EmojiCatalog = {
        guard let url = Bundle.module.url(forResource: "Emoji", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            Logger.viewCycle.error("reaction picker: the bundled emoji list is missing")
            return EmojiCatalog(categories: [])
        }
        return EmojiCatalog.parse(text)
    }()
}

/// The reaction picker popover (MATRIX-111, M2-B4, D-3).
///
/// From the top: the account's recent emoji, a search field, a grid of every
/// emoji by category, and a line with the name of the selected emoji. The
/// search field has focus when the picker opens. Arrow keys move the
/// selection in the grid, Return picks the selection (the first match after
/// a search), and Esc closes the picker. A pick calls `onPick` and closes
/// the picker.
///
/// The picker offers the default (yellow) emoji only; skin tones are not in
/// M2. The search and the arrow-key rules live in `Models.EmojiCatalog` and
/// `Models.EmojiPickerContent`.
///
/// Usage:
/// ```swift
/// .popover(isPresented: $isPicking) {
///     ReactionPickerView(catalog: .bundled, recents: store.emojis) { emoji in
///         toggleReaction(key: emoji)
///     }
/// }
/// ```
public struct ReactionPickerView: View {
    static let columns = 9
    static let cellSize: CGFloat = 32
    static let emojiFontSize: CGFloat = 22
    static let footerEmojiFontSize: CGFloat = 18
    static let padding: CGFloat = 10
    static let gridHeight: CGFloat = 256
    static let cornerRadius: CGFloat = 6

    /// The picker's width: the grid and its padding.
    public static var width: CGFloat {
        CGFloat(columns) * cellSize + 2 * padding
    }

    let catalog: EmojiCatalog
    let recents: [String]
    let onPick: @MainActor (String) -> Void

    @State var query: String
    /// The arrowed grid index. Nil means the first entry.
    @State var selection: Int?
    /// The emoji under the pointer, for the highlight and the name line.
    @State var hoveredValue: String?
    @FocusState var isSearchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - catalog: Every emoji, usually `EmojiCatalog.bundled`.
    ///   - recents: The account's recent emoji, most recent first. The top
    ///     row shows as many as fit.
    ///   - query: The starting search text. Snapshot tests set it.
    ///   - onPick: Called with the picked emoji, before the picker closes.
    public init(
        catalog: EmojiCatalog,
        recents: [String],
        query: String = "",
        onPick: @escaping @MainActor (String) -> Void
    ) {
        self.catalog = catalog
        self.recents = recents
        self.onPick = onPick
        self._query = State(initialValue: query)
    }

    // MARK: - Derived state

    var gridContent: EmojiPickerContent {
        EmojiPickerContent(catalog: catalog, query: query)
    }

    /// The recent emoji the top row shows: distinct, at most one row.
    var recentRow: [String] {
        var row: [String] = []
        for emoji in recents where !emoji.isEmpty && !row.contains(emoji) {
            row.append(emoji)
            if row.count == Self.columns { break }
        }
        return row
    }

    // MARK: - Body

    public var body: some View {
        let visible: EmojiPickerContent = gridContent
        let selected: Int? = visible.effectiveSelection(selection)
        let recentEmoji: [String] = recentRow

        VStack(alignment: .leading, spacing: 8) {
            if !recentEmoji.isEmpty {
                recentsSection(recentEmoji)
            }
            searchField
            grid(visible, selected: selected)
            nameLine(visible, selected: selected)
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .onAppear { isSearchFocused = true }
        .onChange(of: query) { _, _ in selection = nil }
        #if os(macOS)
            .onExitCommand(perform: close)
        #endif
    }

    func recentsSection(_ emoji: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle(Text("Recent"))
            HStack(spacing: 0) {
                ForEach(emoji, id: \.self) { value in
                    cell(value, name: catalog.entry(for: value)?.name, isSelected: false)
                }
            }
        }
    }

    var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search emoji", text: $query)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .onSubmit(pickSelection)
                .onKeyPress(.upArrow) { move(.up) }
                .onKeyPress(.downArrow) { move(.down) }
                .onKeyPress(.leftArrow) { move(.left) }
                .onKeyPress(.rightArrow) { move(.right) }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(Color.primary.opacity(0.06))
        )
    }

    func grid(_ content: EmojiPickerContent, selected: Int?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if content.entries.isEmpty {
                    Text("No emoji found")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.fixed(Self.cellSize), spacing: 0), count: Self.columns),
                    alignment: .leading,
                    spacing: 0
                ) {
                    ForEach(content.sections) { section in
                        Section {
                            ForEach(Array(section.entries.enumerated()), id: \.element.id) { offset, entry in
                                cell(entry.value, name: entry.name, isSelected: section.startIndex + offset == selected)
                            }
                        } header: {
                            if let title = section.title {
                                sectionTitle(Text(verbatim: title))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 6)
                            }
                        }
                    }
                }
            }
            .frame(height: Self.gridHeight)
            .onChange(of: selection) { _, newSelection in
                guard let newSelection, content.entries.indices.contains(newSelection) else { return }
                proxy.scrollTo(content.entries[newSelection].id)
            }
            .onChange(of: query) { _, _ in
                guard let first = content.entries.first else { return }
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

    /// The selected or pointed-at emoji and its CLDR name.
    func nameLine(_ content: EmojiPickerContent, selected: Int?) -> some View {
        let value: String? = hoveredValue ?? selected.map { content.entries[$0].value }
        let name: String? = value.flatMap { catalog.entry(for: $0)?.name }
        return HStack(spacing: 6) {
            if let value {
                Text(verbatim: value)
                    .font(.system(size: Self.footerEmojiFontSize))
            }
            if let name {
                Text(verbatim: name)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .leading)
    }

    func sectionTitle(_ title: Text) -> some View {
        title
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
    }

    func cell(_ value: String, name: String?, isSelected: Bool) -> some View {
        Button {
            pick(value)
        } label: {
            Text(verbatim: value)
                .font(.system(size: Self.emojiFontSize))
                .frame(width: Self.cellSize, height: Self.cellSize)
                .background(
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .fill(highlight(isSelected: isSelected, isHovered: hoveredValue == value))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name ?? value)
        .accessibilityLabel(Text(verbatim: name ?? value))
        .onHover { hovering in
            if hovering {
                hoveredValue = value
            } else if hoveredValue == value {
                hoveredValue = nil
            }
        }
    }

    func highlight(isSelected: Bool, isHovered: Bool) -> Color {
        if isSelected { return Color.accentColor.opacity(0.25) }
        if isHovered { return Color.primary.opacity(0.08) }
        return Color.clear
    }
}

// MARK: - Behavior

extension ReactionPickerView {
    func close() {
        dismiss()
    }

    func pick(_ value: String) {
        onPick(value)
        close()
    }

    /// Return: picks the selection, which is the first match until an arrow
    /// key moves it.
    func pickSelection() {
        let visible: EmojiPickerContent = gridContent
        guard let index = visible.effectiveSelection(selection) else { return }
        pick(visible.entries[index].value)
    }

    func move(_ move: EmojiPickerContent.Move) -> KeyPress.Result {
        let visible: EmojiPickerContent = gridContent
        guard let current = visible.effectiveSelection(selection),
              let next = visible.index(after: move, from: current, columns: Self.columns)
        else { return .ignored }
        hoveredValue = nil
        selection = next
        return .handled
    }
}

#Preview {
    ReactionPickerView(catalog: .bundled, recents: ["😂", "🔥", "👀", "🙏"]) { _ in }
}
