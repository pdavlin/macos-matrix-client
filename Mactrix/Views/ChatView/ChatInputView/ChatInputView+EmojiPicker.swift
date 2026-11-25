import Core
import Models
import SwiftUI
import UI

// MARK: - Emoji picker (MATRIX-234)

/// The emoji button opens the app's emoji picker in a popover on the button:
/// the reaction picker's view, with the recent emoji, the search, and the
/// image packs of the room the message goes to. In a merged chat that room
/// is the send target, and in the thread panel it is the thread's room.
///
/// A pick goes in place of the selection (`ComposerMentionController.insert`),
/// and the popover closes. The text view then takes the focus back, with the
/// cursor after the new text. Control-Command-Space still opens the system
/// Character Viewer: the text view handles that key.
extension ChatInputView {
    /// The emoji button's action.
    func showEmojiPicker() {
        let client = appState.matrixClient
        // The store reads the room's packs again when its last read is old
        // (MATRIX-161), as for the reaction picker.
        client?.loadImagePacks(forRoom: timeline.room.id)
        // A merged chat has no `ChatView` task that reads the list.
        Task { await client?.loadRecentEmojisIfNeeded() }
        isEmojiPickerShown = true
    }

    /// The popover's content.
    var emojiPicker: some View {
        ComposerEmojiPickerContent(
            client: appState.matrixClient,
            roomId: timeline.room.id,
            onClose: { isEmojiPickerShown = false },
            onPick: { insertPickedEmoji($0) }
        )
    }

    /// Puts the pick into the composer. A pick counts as a use in the room
    /// the message goes to (MATRIX-262) and in the account's recent list,
    /// as a reaction pick does; the recent list does not record a custom
    /// emoji.
    private func insertPickedEmoji(_ pick: ComposerEmojiPick) {
        mentions.insert(pick)
        appState.matrixClient?.recordComposerEmojiPick(pick.key, inRoom: timeline.room.id)
    }

    /// When the popover closes (a pick, Esc, or a click outside), the text
    /// view takes the focus. The cursor stays where the text view had it:
    /// after a new emoji.
    func emojiPickerShownDidChange() {
        guard !isEmojiPickerShown, let textView = mentions.textView else { return }
        unsafe textView.window?.makeFirstResponder(textView)
    }
}

/// The picker inside the popover. A view of its own so the recent row, the
/// packs, and the refresh status follow the client through observation while
/// the popover is open, as in the timeline's reaction picker.
private struct ComposerEmojiPickerContent: View {
    let client: MatrixClient?
    /// The room the message goes to. Its image packs are the picker's
    /// custom emoji.
    let roomId: String
    let onClose: @MainActor () -> Void
    let onPick: @MainActor (ComposerEmojiPick) -> Void

    /// The "Refresh Custom Emoji" button of the pack section (MATRIX-161).
    private var packRefresh: UI.ImagePackRefreshControl? {
        guard let client else { return nil }
        return UI.ImagePackRefreshControl(status: client.imagePacks.refreshStatusByRoom[roomId]) { [roomId] in
            client.refreshImagePacks(forRoom: roomId)
        }
    }

    var body: some View {
        UI.ReactionPickerView.composer(
            catalog: .bundled,
            recents: client?.recentEmojis.emojis ?? [],
            packs: client?.imagePacks.packs(forRoom: roomId) ?? [],
            imageLoader: client,
            packRefresh: packRefresh,
            onClose: onClose,
            onPick: onPick
        )
        // The composer's font size is for the message text. The picker
        // keeps the system size, as in the timeline's popover.
        .font(.body)
    }
}
