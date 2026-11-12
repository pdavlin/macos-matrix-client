import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Tokens
import UI

/// A merged chat in the detail area (MATRIX-142 and MATRIX-143, M2.5 Wave
/// 2): one timeline of every member room, and a composer that sends to the
/// right member.
///
/// - The header is the window title and subtitle: the merged chat's name,
///   and each member room's network and name (`MergedChatHeader`).
/// - The timeline is the room timeline's AppKit container with a
///   `MergedLiveTimeline` as its row source. Each row acts on its own
///   member room.
/// - The composer is the room composer with a `MergedComposerSession`.
///
/// Presentation only (contract §11, 2026-11-10): every SDK call goes to one
/// member room through that room's `LiveTimeline`.
///
/// The view follows the merged chat in the account data
/// (`MatrixClient.mergedChats`): a new name or default room applies at once,
/// and a new member list makes a new `MergedLiveTimeline`, because a merged
/// timeline's members are fixed.
struct MergedChatView: View {
    @Environment(AppState.self) private var appState

    /// The merged chat to show, as the selection knew it.
    let merge: MergedChat

    /// The merged chat as the account data holds it now, or the selection's
    /// value while the account data does not hold it.
    private var currentMerge: MergedChat {
        appState.matrixClient?.mergedChats?.merge(id: merge.id) ?? merge
    }

    var body: some View {
        let current = currentMerge
        if let client = appState.matrixClient {
            MergedChatSessionHost(client: client, merge: current)
                .id(MergedChatMembers(id: current.id, rooms: current.rooms))
        }
    }
}

/// The identity of a merged chat's timeline: its ID and its member list.
private struct MergedChatMembers: Hashable {
    let id: String
    let rooms: [String]
}

/// Makes the merged timeline and the composer session once, when the view
/// appears, and keeps them for its life. A new member list gives the host a
/// new identity, so a new pair.
private struct MergedChatSessionHost: View {
    let client: MatrixClient
    let merge: MergedChat

    @State private var session: MergedComposerSession?

    var body: some View {
        Group {
            if let session {
                MergedChatScreen(session: session)
            } else {
                Color(NSColor.controlBackgroundColor)
            }
        }
        .onAppear {
            guard session == nil else { return }
            Logger.mergedChatView.info("opening merged chat \(merge.id, privacy: .public) with \(merge.rooms.count) member(s)")
            let timeline = MergedLiveTimeline(client: client, merge: merge)
            session = MergedComposerSession(timeline: timeline, merge: merge, client: client)
        }
        .onChange(of: merge) { _, newValue in
            session?.update(merge: newValue)
        }
    }
}

/// When the merged timeline marks its members as read.
private struct MergedChatReadKey: Equatable {
    let rowCount: Int
    let active: Bool
    let atBottom: Bool
}

/// The merged chat's timeline, composer, and sheets.
private struct MergedChatScreen: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appearsActive) private var appearsActive

    let session: MergedComposerSession

    private var timeline: MergedLiveTimeline {
        session.timeline
    }

    /// Each member room's label, then the rooms that did not load.
    private var subtitle: String {
        let labels = session.targetOptions.map { option in
            MergedSourceLabel(roomId: option.id, network: option.network, roomName: option.name.isEmpty ? nil : option.name)
        }
        return MergedChatHeader.subtitle(labels: labels, failedCount: timeline.failedRoomIds.count)
    }

    var body: some View {
        TimelineViewRepresentable(merged: timeline, rows: timeline.rows)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .bottomTrailing) {
                if !timeline.isAtBottom {
                    UI.ScrollToBottomChip(unseenCount: timeline.unseenArrivals) {
                        timeline.requestScrollToBottom()
                    }
                    .padding(.trailing, DensityToken.scrollChipMargin)
                    .padding(.bottom, DensityToken.scrollChipMargin)
                    .transition(.opacity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                if let target = session.composerTimeline {
                    ChatInputView(room: target.room.room, timeline: target, replyTo: session.reply, merged: session)
                }
            }
            // Each row acts on its own member timeline, so each member gets
            // the delete confirmation and the forward sheets.
            .background {
                ForEach(session.members, id: \.room.id) { member in
                    Color.clear.timelineActionSheets(timeline: member)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .navigationTitle(session.merge.name)
            .navigationSubtitle(subtitle)
            .frame(minWidth: 250, minHeight: 200)
            // MATRIX-111: the hover row's quick reactions are the recent
            // emoji. One SDK read per session.
            .task {
                await appState.matrixClient?.loadRecentEmojisIfNeeded()
            }
            // The send target moves to the default room 30 minutes after an
            // own last message, without any new activity.
            .task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(60))
                    } catch {
                        return
                    }
                    session.refresh()
                }
            }
            // Read state: while the window is active and the timeline shows
            // the newest rows, every member room is marked read.
            .task(
                id: MergedChatReadKey(rowCount: timeline.rows.count, active: appearsActive, atBottom: timeline.isAtBottom),
                priority: .background
            ) {
                guard appearsActive, timeline.isAtBottom else { return }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                Logger.viewCycle.debug("Mark merged chat members as read")
                await timeline.markMembersAsRead(receiptType: .read)
            }
            // A new time zone moves the day boundaries of the merge.
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                timeline.recomputeAll()
            }
            .onDisappear {
                session.stopTyping()
                let timeline = timeline
                Task {
                    Logger.viewCycle.info("Leaving merged chat, marking its members as read")
                    await timeline.markMembersAsRead(receiptType: .fullyRead)
                }
            }
    }
}
