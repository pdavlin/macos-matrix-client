import Core
import OSLog
import SwiftUI

/// The sync state line at the top of the sidebar.
///
/// MATRIX-123: a healthy sidebar has no line for sync. The view draws
/// nothing while sync runs, so the `List` gets no row and the pinned
/// favourites start at the top. Every other state shows one compact line,
/// with a restart button when sync stopped.
struct SidebarSyncStateView: View {
    @Environment(AppState.self) var appState

    @State var restarting: Bool = false

    /// MATRIX-237: the line, from the sync state and from whether sync ran
    /// before. "Connecting…" shows only before the first `running`.
    private var line: SyncStatusLine {
        appState.matrixClient?.syncStatusLine ?? .signedOut
    }

    /// The text for each line other than `.hidden`.
    private var title: LocalizedStringKey {
        switch line {
        case .connecting:
            "Connecting…"
        case .hidden:
            "Online"
        case .stopped:
            "Sync stopped"
        case .error:
            "Sync error"
        case .offline:
            "Offline"
        case .signedOut:
            "Logged out"
        }
    }

    private var systemImage: String {
        switch line {
        case .connecting, .hidden:
            "arrow.triangle.2.circlepath"
        case .error:
            "exclamationmark.triangle"
        case .stopped, .offline, .signedOut:
            "wifi.slash"
        }
    }

    var body: some View {
        if line != .hidden {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                if line.canRestart {
                    Button("Restart sync") {
                        Task {
                            restarting = true
                            defer { restarting = false }

                            do {
                                try await appState.matrixClient?.startSync()
                            } catch {
                                Logger.viewCycle.error("failed to restart sync: \(error)")
                            }
                        }
                    }
                    .controlSize(.small)
                    .disabled(restarting)
                }
            }
            .font(.callout)
        }
    }
}
