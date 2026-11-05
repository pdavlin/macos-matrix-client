import Models
import SwiftUI

/// Titles and icons for message actions (MATRIX-108).
///
/// The model in `Models` decides what shows; this type decides how it reads.
/// Titles are `LocalizedStringKey`s, so SwiftUI looks them up in the app's
/// strings when a catalog exists.
public enum MessageActionPresentation {
    /// The menu title of `action`.
    public static func title(of action: MessageAction) -> LocalizedStringKey {
        switch action {
        case .reply: "Reply"
        case .replyInThread: "Reply in Thread"
        case let .toggleReaction(key): "\(key)"
        case .openReactionPicker: "Add Reaction…"
        case .edit: "Edit"
        case .copyText: "Copy Text"
        case .copyLink: "Copy Link"
        case .pin: "Pin"
        case .unpin: "Unpin"
        case .quickLook: "Quick Look"
        case .playInline: "Play Inline"
        case .saveToDownloads: "Save to Downloads"
        case .redact: "Delete…"
        case .copyMessages: "Copy Messages"
        }
    }

    /// The tooltip of `action` in the hover row. The hover row keeps its
    /// pre-M2 tooltips.
    public static func hoverTooltip(of action: MessageAction) -> LocalizedStringKey {
        switch action {
        case .toggleReaction, .openReactionPicker: "React"
        case .replyInThread: "Reply in thread"
        default: title(of: action)
        }
    }

    /// The SF Symbol of `action`, or nil for a quick reaction, which draws its
    /// emoji.
    public static func systemImage(of action: MessageAction) -> String? {
        switch action {
        case .reply: "arrowshape.turn.up.left"
        case .replyInThread: "ellipsis.message"
        case .toggleReaction: nil
        case .openReactionPicker: "face.smiling"
        case .edit: "pencil"
        case .copyText: "doc.on.doc"
        case .copyLink: "link"
        case .pin: "pin"
        case .unpin: "pin.slash"
        case .quickLook: "eye"
        case .playInline: "play.rectangle"
        case .saveToDownloads: "arrow.down.circle"
        case .redact: "trash"
        case .copyMessages: "doc.on.clipboard"
        }
    }

    /// The title of the submenu that holds the quick reactions.
    public static var reactionsMenuTitle: LocalizedStringKey {
        "React"
    }

    /// The icon of that submenu.
    public static let reactionsMenuSystemImage = "face.smiling"
}

/// Menu content for message actions: the right-click menu, the menu over a
/// media view, and the Edit-menu section all draw through this view.
///
/// Usage:
/// ```swift
/// .contextMenu {
///     MessageActionMenu(items: MessageActionModel.items(for: subject, on: .contextMenu), perform: perform)
/// }
/// ```
public struct MessageActionMenu: View {
    let entries: [MessageActionMenuEntry]
    let perform: @MainActor (MessageAction) -> Void

    /// - Parameters:
    ///   - items: Ordered items from `MessageActionModel.items(for:on:)`.
    ///   - perform: Runs the chosen action.
    public init(items: [MessageActionItem], perform: @escaping @MainActor (MessageAction) -> Void) {
        self.entries = MessageActionMenuLayout.entries(for: items)
        self.perform = perform
    }

    public var body: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            switch entry {
            case let .action(item):
                button(for: item)
            case let .reactions(items):
                Menu {
                    ForEach(items) { item in
                        Button(MessageActionPresentation.title(of: item.action)) {
                            perform(item.action)
                        }
                        .disabled(!item.isEnabled)
                    }
                } label: {
                    Label(MessageActionPresentation.reactionsMenuTitle, systemImage: MessageActionPresentation.reactionsMenuSystemImage)
                }
                .disabled(!items.contains(where: \.isEnabled))
            case .separator:
                Divider()
            }
        }
    }

    private func button(for item: MessageActionItem) -> some View {
        Button {
            perform(item.action)
        } label: {
            if let systemImage = MessageActionPresentation.systemImage(of: item.action) {
                Label(MessageActionPresentation.title(of: item.action), systemImage: systemImage)
            } else {
                Text(MessageActionPresentation.title(of: item.action))
            }
        }
        .disabled(!item.isEnabled)
    }
}
