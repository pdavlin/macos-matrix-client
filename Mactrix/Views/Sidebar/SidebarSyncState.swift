import Core
import MatrixRustSDK
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

    private var state: SyncServiceState? {
        appState.matrixClient?.syncState
    }

    /// Whether sync runs. Only this state hides the line.
    private var isOnline: Bool {
        state == .running
    }

    /// The text for each state other than `.running`.
    private var title: LocalizedStringKey {
        switch state {
        case .idle:
            "Connecting…"
        case .running:
            "Online"
        case .terminated:
            "Sync stopped"
        case .error:
            "Sync error"
        case .offline:
            "Offline"
        case nil:
            "Logged out"
        }
    }

    private var systemImage: String {
        switch state {
        case .idle, .running:
            "arrow.triangle.2.circlepath"
        case .error:
            "exclamationmark.triangle"
        case .terminated, .offline, nil:
            "wifi.slash"
        }
    }

    var canRestart: Bool {
        [.error, .offline, .terminated].contains(where: { $0 == state })
    }

    var body: some View {
        if !isOnline {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 4)

                if canRestart {
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
