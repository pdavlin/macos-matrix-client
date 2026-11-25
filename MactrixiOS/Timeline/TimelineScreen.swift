import Core
import MatrixRustSDK
import Models
import OSLog
import SwiftUI
import Tokens
import UI
import UIKit

/// The iOS timeline for one joined room (MATRIX-85). The single entry point
/// the room list's detail opens, through `LiveRoomScreen` (MATRIX-102).
///
/// It owns the room's `LiveTimeline`, created once on first appearance: a
/// timeline configures an SDK timeline when it is created, so it must not be
/// created again on every view init.
///
/// A thread chip or "Reply in Thread" pushes the thread screen over it
/// (MATRIX-245, `ThreadScreen`).
struct TimelineScreen: View {
    let room: LiveRoom
    let imageLoader: (any UI.ImageLoader)?

    @State private var timeline: LiveTimeline?
    /// The thread screen pushed over the room, or nil (MATRIX-245).
    @State private var openThread: ThreadScreenRequest?

    init(room: LiveRoom, imageLoader: (any UI.ImageLoader)? = nil) {
        self.room = room
        self.imageLoader = imageLoader
    }

    var body: some View {
        Group {
            if let timeline {
                LiveTimelineContainer(timeline: timeline, imageLoader: imageLoader) { request in
                    openThread = request
                }
            } else {
                Color(.systemBackground)
            }
        }
        .navigationTitle(room.displayName ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .threadDestination($openThread) { request in
            ThreadScreen(room: room, request: request, imageLoader: imageLoader)
        }
        .onAppear {
            if timeline?.room.id != room.id {
                timeline = LiveTimeline(room: room)
            }
        }
    }
}

/// The container for a live timeline, plus the read receipts the Mac
/// `ChatJoinedRoom` sends. The room screen and the thread screen
/// (MATRIX-245) both show one.
///
/// Only a room timeline sends read receipts. The Mac thread panel sends
/// none, so the thread screen sends none either.
struct LiveTimelineContainer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    let timeline: LiveTimeline
    let imageLoader: (any UI.ImageLoader)?
    /// Pushes the thread screen (MATRIX-245). The thread screen gives none:
    /// its root draws no chip, and its "Reply in Thread" replies in place.
    let openThread: @MainActor (ThreadScreenRequest) -> Void

    @State private var feed: LiveTimelineFeed?
    @State private var composerTarget: LiveComposerTarget?
    /// Raised to put the keyboard focus in the composer (`ComposerBar`).
    @State private var composerFocusRequest: Int

    /// - Parameters:
    ///   - focusesComposer: true when the composer takes the keyboard focus
    ///     at open: a thread screen opened by "Reply in Thread".
    init(
        timeline: LiveTimeline,
        imageLoader: (any UI.ImageLoader)?,
        focusesComposer: Bool = false,
        openThread: @escaping @MainActor (ThreadScreenRequest) -> Void = { _ in }
    ) {
        self.timeline = timeline
        self.imageLoader = imageLoader
        self.openThread = openThread
        _composerFocusRequest = State(initialValue: focusesComposer ? 1 : 0)
    }

    private var isRoomTimeline: Bool {
        timeline.focusedThreadId == nil
    }

    private var ownUserId: String {
        (try? appState.matrixClient?.userSession().userID) ?? ""
    }

    private var mediaLoader: (any TimelineMediaLoading)? {
        // `client` is nil until a session is restored, and again after sign out.
        guard let client = appState.matrixClient?.client else { return nil }
        return LiveMediaLoader(client: client)
    }

    var body: some View {
        Group {
            if let feed, let composerTarget {
                ConversationLayout {
                    TimelineContainer(
                        feed: feed,
                        timeline: timeline,
                        imageLoader: imageLoader,
                        ownUserId: ownUserId,
                        showsReadReceipts: timeline.room.roomInfo?.isDirect == true,
                        media: mediaLoader,
                        ownAvatarUrl: appState.matrixClient?.ownAvatarUrl,
                        repliesInThreads: timeline.repliesInThreads,
                        openThread: openThread,
                        focusComposer: { composerFocusRequest += 1 }
                    )
                } composer: {
                    ComposerBar(
                        target: composerTarget,
                        placeholder: ComposerPlaceholder.text(
                            isThreadTimeline: !isRoomTimeline,
                            mergedPlaceholder: nil,
                            roomName: timeline.room.displayName
                        ),
                        focusRequest: composerFocusRequest
                    )
                    // A new room starts with an empty field.
                    .id(ObjectIdentifier(composerTarget))
                }
            } else {
                Color(.systemBackground)
            }
        }
        .onAppear {
            if feed?.timeline !== timeline {
                feed = LiveTimelineFeed(timeline: timeline)
                composerTarget = LiveComposerTarget(timeline: timeline)
            }
        }
        .task(id: ReadKey(count: timeline.timelineItems.count, active: scenePhase == .active), priority: .background) {
            guard isRoomTimeline, scenePhase == .active else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                try await timeline.timeline?.markAsRead(receiptType: .read)
            } catch is CancellationError {
                /* sleep cancelled */
            } catch {
                Logger.timelineIOS.error("failed to send timeline read receipt: \(error)")
            }
        }
        .onDisappear {
            // The room screen also disappears under a pushed thread screen
            // (MATRIX-245), as it does when the room closes.
            guard isRoomTimeline else { return }
            Task {
                do {
                    try await timeline.timeline?.markAsRead(receiptType: .fullyRead)
                } catch {
                    Logger.timelineIOS.error("failed to mark room as read: \(error)")
                }
            }
        }
    }

    private struct ReadKey: Equatable {
        let count: Int
        let active: Bool
    }
}

/// The scroll container with its floating scroll-to-bottom chip. Feed-generic,
/// so the DEBUG fixture shows the same container a live room does.
struct TimelineContainer: View {
    let feed: TimelineFeed
    let timeline: LiveTimeline?
    let imageLoader: (any UI.ImageLoader)?
    let ownUserId: String
    /// D-3: receipts render in direct rooms only.
    let showsReadReceipts: Bool
    var media: (any TimelineMediaLoading)?
    var fallbackActions: (any TimelineFallbackRowActions)?
    /// The account's global profile avatar (MATRIX-163).
    var ownAvatarUrl: String?
    /// Thread entry points (MATRIX-245, MATRIX-246): see `TimelineRowContext`.
    var repliesInThreads = false
    var openThread: @MainActor (ThreadScreenRequest) -> Void = { _ in }
    var focusComposer: @MainActor () -> Void = {}

    /// The file the full-screen viewer shows. Presented from here, not from
    /// a cell: a cell is recycled or reconfigured at any update.
    @State private var viewerItem: MediaViewerItem?

    @AppStorage(TypographyToken.fontSizeStorageKey) private var fontSize = TypographyToken.defaultBaseFontSize

    private var typography: TimelineTypography {
        TimelineTypography(base: CGFloat(fontSize))
    }

    var body: some View {
        TimelineCollectionRepresentable(
            feed: feed,
            rowContext: TimelineRowContext(
                timeline: timeline,
                imageLoader: imageLoader,
                ownUserId: ownUserId,
                showsReadReceipts: showsReadReceipts,
                typography: typography,
                retryPagination: { [feed] in feed.retryPagination() },
                media: media,
                openMedia: { viewerItem = $0 },
                fallbackActions: fallbackActions,
                ownAvatarUrl: ownAvatarUrl,
                repliesInThreads: repliesInThreads,
                openThread: openThread,
                focusComposer: focusComposer
            )
        )
        .overlay(alignment: .bottomTrailing) {
            if !feed.isAtBottom {
                // An opaque control, not glass: it floats over the timeline,
                // and the glass rule keeps glass off scrollable content.
                UI.ScrollToBottomChip(unseenCount: feed.unseenArrivals) {
                    feed.requestScrollToBottom()
                }
                .environment(\.timelineTypography, typography)
                .padding(.trailing, DensityToken.scrollChipMargin)
                .padding(.bottom, DensityToken.scrollChipMargin)
                .transition(.opacity)
            }
        }
        .background(Color(.systemBackground))
        .fullScreenCover(item: $viewerItem) { item in
            MediaViewerScreen(item: item)
        }
    }
}

/// The timeline above the composer (MATRIX-86).
///
/// The keyboard shrinks the stack from the bottom. The collection view is
/// flipped, so its content offset is measured from the newest message, and a
/// timeline at the bottom stays there as its height changes.
struct ConversationLayout<TimelineContent: View, ComposerContent: View>: View {
    @ViewBuilder let timeline: TimelineContent
    @ViewBuilder let composer: ComposerContent

    var body: some View {
        VStack(spacing: 0) {
            timeline
            composer
        }
    }
}

/// Hosts the controller's collection view in SwiftUI.
struct TimelineCollectionRepresentable: UIViewRepresentable {
    let feed: TimelineFeed
    let rowContext: TimelineRowContext

    func makeCoordinator() -> TimelineCollectionController {
        TimelineCollectionController(feed: feed, rowContext: rowContext)
    }

    func makeUIView(context: Context) -> UICollectionView {
        context.coordinator.collectionView
    }

    /// Feed changes reach the controller through observation tracking, not
    /// through here. This only hands over a new row context.
    func updateUIView(_: UICollectionView, context: Context) {
        let controller = context.coordinator
        let old = controller.rowContext
        controller.rowContext = rowContext
        controller.rowContextDidChange(from: old)
    }

    static func dismantleUIView(_: UICollectionView, coordinator: TimelineCollectionController) {
        coordinator.stopRowUpdateDrain()
    }
}
