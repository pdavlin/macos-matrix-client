import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import UI

struct InspectorUserInfo: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState

    let userId: String

    @State private var profile: MatrixRustSDK.UserProfile?

    var isUserIgnored: Bool {
        appState.matrixClient?.ignoredUserIds.contains(userId) == true
    }

    /// The "Timeline" actions when a joined room is selected: "Mention"
    /// inserts a chip in that room's composer (MATRIX-105). The chip shows the
    /// member's room display name, else the global profile name.
    var timelineActions: ComposerMentionTimelineActions? {
        guard case let .joinedRoom(timeline: timeline) = windowState.selectedScreen else { return nil }
        let roomName = timeline.room.members.first { $0.userId == userId }?.displayName
        return ComposerMentionTimelineActions(
            timeline: timeline,
            target: MentionTarget(userId: userId, displayName: roomName ?? profile?.displayName)
        )
    }

    @ViewBuilder
    var content: some View {
        if let profile {
            UI.UserProfileView(
                profile: profile,
                isUserIgnored: isUserIgnored,
                actions: appState.matrixClient?.userProfileActions(forUserId: userId, windowState: windowState),
                timelineActions: timelineActions,
                imageLoader: appState.matrixClient
            )
        } else {
            UI.UserProfileView(
                profile: MockUserProfile(),
                isUserIgnored: isUserIgnored,
                actions: nil,
                timelineActions: nil,
                imageLoader: appState.matrixClient
            )
            .redacted(reason: .placeholder)
        }
    }

    var body: some View {
        content
            .task(id: userId) {
                guard let matrixClient = appState.matrixClient else { return }

                do {
                    profile = try await matrixClient.client.getProfile(userId: userId)
                } catch {
                    Logger.viewCycle.error("failed to get profile \(error)")
                }
            }
    }
}
