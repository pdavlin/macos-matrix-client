import Core
import MatrixRustSDK
import OSLog
import SwiftUI
import Tokens
import UI
import UIKit

/// The iOS timeline for one joined room (MATRIX-85). The single entry point
/// the room list's detail placeholder swaps for.
///
/// It owns the room's `LiveTimeline`, created once on first appearance: a
/// timeline configures an SDK timeline when it is created, so it must not be
/// created again on every view init.
struct TimelineScreen: View {
    let room: LiveRoom
    let imageLoader: (any UI.ImageLoader)?

    @State private var timeline: LiveTimeline?

    init(room: LiveRoom, imageLoader: (any UI.ImageLoader)? = nil) {
        self.room = room
        self.imageLoader = imageLoader
    }

    var body: some View {
        Group {
            if let timeline {
                LiveTimelineContainer(timeline: timeline, imageLoader: imageLoader)
            } else {
                Color(.systemBackground)
            }
        }
        .navigationTitle(room.displayName ?? "Room")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if timeline?.room.id != room.id {
                timeline = LiveTimeline(room: room)
            }
        }
    }
}

/// The container for a live timeline, plus the read receipts the Mac
/// `ChatJoinedRoom` sends.
private struct LiveTimelineContainer: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    let timeline: LiveTimeline
    let imageLoader: (any UI.ImageLoader)?

    @State private var feed: LiveTimelineFeed?

    private var ownUserId: String {
        (try? appState.matrixClient?.userSession().userID) ?? ""
    }

    var body: some View {
        Group {
            if let feed {
                TimelineContainer(
                    feed: feed,
                    timeline: timeline,
                    imageLoader: imageLoader,
                    ownUserId: ownUserId,
                    showsReadReceipts: timeline.room.roomInfo?.isDirect == true
                )
            } else {
                Color(.systemBackground)
            }
        }
        .onAppear {
            if feed?.timeline !== timeline {
                feed = LiveTimelineFeed(timeline: timeline)
            }
        }
        .task(id: ReadKey(count: timeline.timelineItems.count, active: scenePhase == .active), priority: .background) {
            guard scenePhase == .active else { return }
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
                retryPagination: { [feed] in feed.retryPagination() }
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
