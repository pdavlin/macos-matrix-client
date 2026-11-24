import Foundation

/// The active filter chip in the sidebar header (MATRIX-226): what the chat
/// list shows when it is not the plain Inbox.
///
/// The chip names the rail item (a label or a space) and the list filter
/// (Unread, People, …), as the list's section title does: "Work",
/// "Unread", or "Work · Unread". Its tint is the label's color, the color of
/// the space's initials square, or the accent for a list filter alone. A
/// click on the chip goes back to the Inbox: the rail and the list filter
/// both.
public struct ChatListActiveFilter: Equatable, Sendable {
    /// The chip's color.
    public enum Tint: Equatable, Sendable {
        /// The accent color: a list filter with the Inbox on the rail.
        case accent
        /// A label palette color by index. Nil is the neutral fill of a
        /// label with no color.
        case palette(Int?)
    }

    public var title: String
    /// The SF Symbol before the title: the label's icon, the space glyph,
    /// or the list filter's symbol.
    public var systemImage: String
    public var tint: Tint

    public init(title: String, systemImage: String, tint: Tint) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    /// The symbol of a space on the chip: the glyph of a space with no name
    /// on the rail (`SpaceRailIcon`).
    public static let spaceSymbol = "square.grid.2x2"

    /// The symbol of a label with no icon of its own.
    public static let labelSymbol = "tag"

    /// The chip for the window's filters, or nil for the plain Inbox (no
    /// chip).
    ///
    /// - Parameters:
    ///   - rail: the rail selection, resolved as the chat list resolves it
    ///     (a label or a space that is not on the rail is the Inbox).
    ///   - list: the chat-list filter.
    ///   - labels: the labels document.
    ///   - spaceName: the name of a space by its room ID, or nil when the
    ///     space is not known; an unknown space counts as the Inbox.
    ///   - paletteCount: the number of label colors, for a space's color.
    public static func chip(
        rail: ChatListRailFilter,
        list: ChatListFilter,
        labels: ChatLabelDocument,
        spaceName: (String) -> String?,
        paletteCount: Int
    ) -> ChatListActiveFilter? {
        let railChip: ChatListActiveFilter? = switch rail {
        case .inbox:
            nil
        case let .label(id):
            labels.label(id: id).map { label in
                ChatListActiveFilter(
                    title: label.name,
                    systemImage: label.icon ?? labelSymbol,
                    tint: .palette(label.colorIndex)
                )
            }
        case let .space(id):
            spaceName(id).map { name in
                ChatListActiveFilter(
                    title: name,
                    systemImage: spaceSymbol,
                    tint: .palette(ChatListRailSpace(id: id, name: name).colorIndex(paletteCount: paletteCount))
                )
            }
        }
        guard var chip = railChip else {
            return list == .inbox ? nil : ChatListActiveFilter(title: list.title, systemImage: list.systemImage, tint: .accent)
        }
        if list != .inbox {
            chip.title += " · \(list.title)"
        }
        return chip
    }
}

/// The chat list's section header under the filter chip (MATRIX-226).
///
/// The chip names the filter, so while it shows, the header leaves out the
/// list's title and keeps only the Broadcast button (MATRIX-168). With
/// neither a title nor the button, the list draws no header at all, so no
/// empty band shows.
public struct ChatListSectionHeader: Equatable, Sendable {
    /// The list's title, or nil while the chip names the filter.
    public var title: String?
    /// The name of the label or space the Broadcast button sends to, or nil
    /// with no button.
    public var broadcastName: String?

    /// - Parameters:
    ///   - listTitle: the list's title ("Inbox", "Work · Unread").
    ///   - activeFilter: the chip the sidebar header shows
    ///     (`ChatListActiveFilter.chip`), or nil for none.
    ///   - broadcastName: the Broadcast button's target, or nil.
    public init(listTitle: String, activeFilter: ChatListActiveFilter?, broadcastName: String?) {
        title = activeFilter == nil ? listTitle : nil
        self.broadcastName = broadcastName
    }

    /// True when the header has nothing to show: the list leaves it out.
    public var isEmpty: Bool {
        title == nil && broadcastName == nil
    }
}
