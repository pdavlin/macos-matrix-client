import Core
import Foundation
import SwiftUI

/// The sync state the chat list shows (MATRIX-242), and the action of its
/// Retry button.
struct RoomListSync {
    /// The shared rule of the Mac sidebar's line (MATRIX-237).
    let line: SyncStatusLine
    /// Starts sync again: the MATRIX-237 restart path.
    let retry: @MainActor () async -> Void
}

/// What the line shows for each `SyncStatusLine`: the text and the symbol of
/// the Mac sidebar's line, and Retry where the Mac shows "Restart sync".
struct RoomListSyncLineContent {
    let title: LocalizedStringResource
    let systemImage: String
    let showsRetry: Bool

    /// Nil while sync runs: the list shows no line, as the Mac sidebar.
    init?(_ line: SyncStatusLine) {
        switch line {
        case .hidden:
            return nil
        case .connecting:
            title = "Connecting…"
            systemImage = "arrow.triangle.2.circlepath"
        case .stopped:
            title = "Sync stopped"
            systemImage = "wifi.slash"
        case .error:
            title = "Sync error"
            systemImage = "exclamationmark.triangle"
        case .offline:
            title = "Offline"
            systemImage = "wifi.slash"
        case .signedOut:
            title = "Logged out"
            systemImage = "wifi.slash"
        }
        showsRetry = line.canRestart
    }
}

/// The sync line at the bottom of the chat list (MATRIX-242).
///
/// Navigation chrome, not a row: the shell puts it in the list's bottom
/// safe-area inset, so the rows scroll under it. It draws nothing while sync
/// runs.
struct RoomListSyncLine: View {
    let sync: RoomListSync

    @State private var isRetrying = false

    var body: some View {
        if let content = RoomListSyncLineContent(sync.line) {
            HStack(spacing: 12) {
                Label {
                    Text(content.title)
                } icon: {
                    Image(systemName: content.systemImage)
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if content.showsRetry {
                    Button("Retry") {
                        Task {
                            isRetrying = true
                            defer { isRetrying = false }
                            await sync.retry()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(isRetrying)
                    .accessibilityIdentifier("syncRetryButton")
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 8)
            .accessibilityIdentifier("syncStatusLine")
        }
    }
}
