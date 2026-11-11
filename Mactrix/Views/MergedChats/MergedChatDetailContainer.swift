import Core
import Models
import SwiftUI

/// The detail area of a selected merged chat (MATRIX-141 Phase B): the merged
/// timeline and composer (`MergedChatView`, MATRIX-142 and MATRIX-143).
///
/// It reads the merged chat from the live document. A merged chat the
/// document does not hold (a restored window before the first read of the
/// merged chats) shows the empty state.
struct MergedChatDetailContainer: View {
    @Environment(AppState.self) private var appState

    let mergedChatId: String

    var body: some View {
        if let merge = appState.matrixClient?.mergedChats?.merge(id: mergedChatId) {
            MergedChatView(merge: merge)
        } else {
            ContentUnavailableView("Select a room", systemImage: "message.fill")
        }
    }
}
