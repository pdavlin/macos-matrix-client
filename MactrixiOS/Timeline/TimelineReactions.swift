import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

// MATRIX-249: reactions on iOS. A tap on a chip toggles the reaction, a long
// press on a chip shows who reacted (`ReactionChipPeopleCard`, in the shared
// chip), and the message's long-press menu starts with the room's quick
// reactions and "Add Reaction…", which opens the shared picker in a sheet.
// Every toggle goes through the shared
// `LiveTimeline.toggleReaction(key:on:recordingUseIn:)`, the Mac's one path,
// which records an added reaction as a use in the room (MATRIX-262).

/// The reaction entries of the iOS long-press menu (MATRIX-249).
///
/// The shared action model decides them, as it decides the Mac right-click
/// menu (`MessageActionModel`, surface `.contextMenu`): the room's three
/// quick reactions (MATRIX-262, `MatrixClient.quickReactionKeys(forRoom:)`),
/// then "Add Reaction…". A redacted message has none.
///
/// The entries are the first items of the menu, one item each, not a row of
/// emoji inside the menu. A row in a system menu is a `ControlGroup`, which
/// the system draws as icons, with or without short titles. An emoji is
/// text, not an icon, and no simulator run could show how such a row draws
/// it (MATRIX-249). A custom emoji is an image that a menu takes only when
/// it is already loaded. A plain item always draws the emoji, in color.
enum TimelineReactionMenu {
    /// - Parameters:
    ///   - subject: the message.
    ///   - quickReactionKeys: the room's quick reactions, in order.
    /// - Returns: the enabled reaction actions, in menu order.
    static func actions(for subject: MessageActionSubject, quickReactionKeys: [String]) -> [MessageAction] {
        MessageActionModel.items(for: subject, on: .contextMenu, quickReactionKeys: quickReactionKeys)
            .filter { $0.isEnabled && ($0.action.isQuickReaction || $0.action == .openReactionPicker) }
            .map(\.action)
    }

    /// The keys of the message's reactions that the account posted. A quick
    /// reaction with one of these keys shows a check, and a tap removes it.
    static func ownKeys<Reaction: Models.Reaction>(of reactions: [Reaction], ownUserId: String) -> Set<String> {
        Set(reactions.filter { $0.senders.contains { $0.senderId == ownUserId } }.map(\.key))
    }
}

/// A request to show the reaction picker sheet on one message (MATRIX-249).
///
/// The timeline container presents the sheet, not the cell: a cell is
/// recycled or reconfigured at any update.
struct TimelineReactionPickerRequest: Identifiable {
    /// The message the picked emoji reacts to.
    let itemId: MatrixRustSDK.EventOrTransactionId

    var id: String { itemId.id }
}

@MainActor
extension TimelineRowContext {
    /// The quick reactions of the long-press menu: the room's ranked
    /// reactions (MATRIX-262), as the Mac hover row and menus have them. The
    /// defaults where no client or timeline is: the DEBUG fixture.
    var quickReactionKeys: [String] {
        guard let client, let roomId = timeline?.room.id else { return MessageActionModel.defaultQuickReactionKeys }
        return client.quickReactionKeys(forRoom: roomId)
    }

    /// The shortcode of a custom emoji key, from the room's image packs in
    /// memory (MATRIX-166), as the Mac row has it. Nil where no client or
    /// timeline is.
    var reactionEmojiName: (@MainActor (String) -> String?)? {
        guard let client, let roomId = timeline?.room.id else { return nil }
        return { url in client.imagePacks.shortcode(forImageUrl: url, inRoom: roomId) }
    }

    /// Toggles the account's own reaction `key` on a message through the
    /// shared Core path, which records an added reaction as a use
    /// (MATRIX-262). A chip tap, a chip's long-press menu, a quick reaction
    /// of the message menu, and a pick in the picker sheet all end here.
    func toggleReaction(key: String, on itemId: MatrixRustSDK.EventOrTransactionId) {
        guard let timeline else {
            Logger.timelineIOS.error("toggle reaction: no live timeline for \(itemId.id, privacy: .public)")
            return
        }
        let client = client
        Logger.timelineIOS.info("toggle reaction on \(itemId.id, privacy: .public)")
        Task {
            await timeline.toggleReaction(key: key, on: itemId, recordingUseIn: client)
        }
    }
}

/// The reaction entries at the top of a message's long-press menu, then a
/// divider (MATRIX-249).
struct TimelineReactionMenuSection<Reaction: Models.Reaction>: View {
    let subject: MessageActionSubject
    /// The message's reactions: the own ones show a check.
    let reactions: [Reaction]
    let context: TimelineRowContext
    let perform: @MainActor (MessageAction) -> Void

    var body: some View {
        let actions = TimelineReactionMenu.actions(for: subject, quickReactionKeys: context.quickReactionKeys)
        let ownKeys = TimelineReactionMenu.ownKeys(of: reactions, ownUserId: context.ownUserId)
        ForEach(actions, id: \.self) { action in
            TimelineReactionMenuItem(
                action: action,
                ownKeys: ownKeys,
                imageLoader: context.imageLoader,
                emojiName: context.reactionEmojiName,
                perform: perform
            )
        }
        if !actions.isEmpty {
            Divider()
        }
    }
}

/// One reaction entry of the long-press menu (MATRIX-249): a quick reaction
/// as a toggle with its emoji as the title, or "Add Reaction…".
///
/// A custom emoji (`mxc://`) has its shortcode as the title when the room's
/// image packs know it, else "Custom Emoji", as in the Mac menus. Its image
/// is the item's icon when the image loader has it in its cache: a system
/// menu takes no image that is still to load.
struct TimelineReactionMenuItem: View {
    let action: MessageAction
    /// The keys of the message's reactions that the account posted
    /// (`TimelineReactionMenu.ownKeys(of:ownUserId:)`). A quick reaction
    /// with one of them shows a check, and a tap removes the reaction.
    let ownKeys: Set<String>
    let imageLoader: (any UI.ImageLoader)?
    let emojiName: (@MainActor (String) -> String?)?
    let perform: @MainActor (MessageAction) -> Void

    var body: some View {
        if case let .toggleReaction(key) = action {
            let isOwn = ownKeys.contains(key)
            Toggle(isOn: Binding(get: { isOwn }, set: { _ in perform(action) })) {
                reactionLabel(key: key)
            }
        } else {
            Button {
                perform(action)
            } label: {
                Label(UI.MessageActionPresentation.title(of: action), systemImage: Self.pickerSystemImage)
            }
        }
    }

    /// The icon of "Add Reaction…": the shared one, as on the Mac.
    private static let pickerSystemImage = UI.MessageActionPresentation.systemImage(of: .openReactionPicker)
        ?? UI.MessageActionPresentation.reactionsMenuSystemImage

    @ViewBuilder
    private func reactionLabel(key: String) -> some View {
        if case let .image(mxcUrl) = ReactionKeyKind(key: key) {
            Label {
                if let name = emojiName?(mxcUrl), !name.isEmpty {
                    Text(verbatim: ":\(name):")
                } else {
                    Text(UI.MessageActionPresentation.title(of: action))
                }
            } icon: {
                if let image = imageLoader?.cachedImage(matrixUrl: mxcUrl) {
                    image.renderingMode(.original)
                } else {
                    Image(systemName: UI.MessageActionPresentation.reactionsMenuSystemImage)
                }
            }
        } else {
            Text(verbatim: key)
        }
    }
}

/// The reaction picker of the long-press menu (MATRIX-249): the shared
/// `ReactionPickerView` in a sheet, with the account's recent emoji and the
/// custom emoji of the room's workspace (MATRIX-155), as the Mac popover has
/// them (`TimelineReactionPickerContent`). The body reads both through
/// observation, so a list that loads after the sheet opens shows.
///
/// A pick calls `onPick`, and the picker closes its sheet through the
/// environment's `dismiss`. A sheet is the navigation layer, so it keeps
/// the system's sheet background.
struct TimelineReactionPickerSheet: View {
    let client: MatrixClient?
    /// The room the reaction goes to.
    let roomId: String
    let imageLoader: (any UI.ImageLoader)?
    let onPick: @MainActor (String) -> Void

    /// The space over the picker, under the sheet's grabber.
    static let topPadding: CGFloat = 16

    /// The "Refresh Custom Emoji" button of the pack section (MATRIX-161).
    private var packRefresh: UI.ImagePackRefreshControl? {
        guard let client else { return nil }
        return UI.ImagePackRefreshControl(status: client.imagePacks.refreshStatusByRoom[roomId]) { [roomId] in
            client.refreshImagePacks(forRoom: roomId)
        }
    }

    var body: some View {
        UI.ReactionPickerView(
            catalog: .bundled,
            recents: client?.recentEmojis.emojis ?? [],
            packs: client?.imagePacks.packs(forRoom: roomId) ?? [],
            imageLoader: imageLoader,
            packRefresh: packRefresh,
            onPick: onPick
        )
        .padding(.top, Self.topPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            // As the Mac picker does when it opens: the store reads the
            // workspace again only when its last read is old (MATRIX-161).
            client?.loadImagePacks(forRoom: roomId)
            await client?.loadRecentEmojisIfNeeded()
        }
    }
}
