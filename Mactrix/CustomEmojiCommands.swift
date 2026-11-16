import Core
import Models
import SwiftUI

/// View > Refresh Custom Emoji (MATRIX-161).
///
/// Reads the image pack of the workspace of the key window's chat now, as
/// the button in the reaction picker's pack section does. The item is
/// disabled in a chat with no known parent space, in a merged chat, on any
/// other screen, and during a refresh. Its title carries the busy state and,
/// for a few seconds, the outcome; the picker's header shows the same state.
struct CustomEmojiCommands: Commands {
    let appState: AppState

    @FocusedValue(WindowState.self) private var windowState: WindowState?

    /// The room of the key window's chat, or nil on any other screen.
    private var roomId: String? {
        guard case let .joinedRoom(timeline: timeline) = windowState?.selectedScreen else { return nil }
        return timeline.room.id
    }

    static func title(for status: ImagePackStore.RefreshStatus?) -> String {
        switch status {
        case nil:
            "Refresh Custom Emoji"
        case .busy:
            "Refreshing Custom Emoji…"
        case let .loaded(emojiCount: count):
            "Refresh Custom Emoji (\(count) Loaded)"
        case .failed:
            "Refresh Custom Emoji (Failed)"
        }
    }

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            let client: MatrixClient? = appState.matrixClient
            let roomId: String? = roomId
            let status: ImagePackStore.RefreshStatus? = roomId.flatMap { client?.imagePacks.refreshStatusByRoom[$0] }
            let hasSpace: Bool = roomId.map { client?.imagePacks.hasSpace(forRoom: $0) ?? false } ?? false

            Divider()
            Button(Self.title(for: status)) {
                guard let roomId else { return }
                client?.refreshImagePacks(forRoom: roomId)
            }
            .disabled(!hasSpace || status == .busy)
        }
    }
}
