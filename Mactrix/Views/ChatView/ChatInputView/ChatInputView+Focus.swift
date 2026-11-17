import Core
import MatrixRustSDK
import Models
import SwiftUI

// MARK: - Focus (MATRIX-188)

extension ChatInputView {
    /// Takes the window's focus request when it is for this chat
    /// (MATRIX-188). The text view takes the focus once it is in the window
    /// and the draft has loaded, with the cursor at the end of the draft.
    func takeFocusRequest() {
        let chat: ChatSelection = merged.map { .merged($0.merge.id) } ?? .room(timeline.room.id)
        guard windowState.takeComposerFocusRequest(composerChat: chat, membership: room.membership().asModel) else {
            return
        }
        focusSerial += 1
    }
}
