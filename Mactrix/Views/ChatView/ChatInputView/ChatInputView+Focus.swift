import Core
import MatrixRustSDK
import Models
import SwiftUI

// MARK: - Focus (MATRIX-188)

extension ChatInputView {
    /// Takes the window's focus request when it is for this chat
    /// (MATRIX-188). The text view takes the focus once it is in the window
    /// and the draft has loaded, with the cursor at the end of the draft.
    ///
    /// A thread panel's composer takes only the request of "Reply in
    /// Thread" on its root, and the room's main composer only the requests
    /// that open the chat (MATRIX-216).
    func takeFocusRequest() {
        let chat: ChatSelection = merged.map { .merged($0.merge.id) } ?? .room(timeline.room.id)
        guard windowState.takeComposerFocusRequest(
            composerChat: chat,
            threadRoot: timeline.focusedThreadId,
            membership: room.membership().asModel
        ) else {
            return
        }
        focusSerial += 1
    }
}

// MARK: - Thread panel (MATRIX-216)

extension ChatInputView {
    /// The root of the thread that the window's thread panel shows in this
    /// composer's room, or nil. A reply to that root goes into its thread
    /// (`Models.ReplyRoute`), also from the main composer.
    var openThreadRoot: String? {
        windowState.openThreadPanel?.rootEventId(inRoom: timeline.room.id)
    }
}
