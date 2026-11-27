import Core
import Models
import SwiftUI
import UI

/// The thread screen (MATRIX-245): one thread of a room, with a composer
/// that sends into the thread.
///
/// It is the iOS twin of the Mac thread panel (`WindowState.focusThread`):
/// a `LiveTimeline(room:focusThread:)` over the room's `LiveRoom`, which
/// loads the whole thread when it opens (MATRIX-229, `ThreadBackfill`), in
/// the same collection-view container as the room. Its composer sends
/// through the shared reply route, so every message goes into the thread and
/// the SDK adds the thread relation (`LiveTimeline+ReplyRoute`).
///
/// The room's screen pushes it (`View.threadDestination`): on iPhone onto the
/// app's navigation stack, on iPad onto the detail column's stack. The
/// timeline lives in view state, so a pop releases it with its SDK timeline
/// and listeners.
struct ThreadScreen: View {
    let room: LiveRoom
    let request: ThreadScreenRequest
    let imageLoader: (any UI.ImageLoader)?

    @State private var timeline: LiveTimeline?

    var body: some View {
        Group {
            if let timeline {
                LiveTimelineContainer(
                    timeline: timeline,
                    imageLoader: imageLoader,
                    focusesComposer: request.focusesComposer
                )
            } else {
                Color(.systemBackground)
            }
        }
        .navigationTitle(ThreadPanelHeaderText.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ThreadScreenTitle(roomName: room.displayName, replyCount: timeline?.threadFacts.replyCount)
            }
            // Two lines of text, not a control: no capsule behind them.
            .sharedBackgroundVisibility(.hidden)
            // MATRIX-261: Follow Thread or Unfollow Thread.
            if let follow = timeline?.threadFollow {
                ToolbarItem(placement: .topBarTrailing) {
                    ThreadFollowButton(model: follow)
                }
            }
        }
        // Read when the thread opens (MATRIX-261).
        .task(id: timeline.map { ObjectIdentifier($0) }) { await timeline?.threadFollow?.load() }
        .onAppear {
            guard timeline?.focusedThreadId != request.rootEventId else { return }
            let thread = LiveTimeline(room: room, focusThread: request.rootEventId)
            // "Reply in Thread" on a message inside the thread quotes it
            // there (`ThreadReplyStart`), as the Mac thread panel does.
            thread.sendReplyTo = request.quotedMessage
            timeline = thread
        }
    }
}

/// The title of the thread screen (MATRIX-245): "Thread", and under it the
/// room and the reply count, the text of the Mac panel header
/// (`ThreadPanelHeaderText`). It sits in the navigation bar, which is the
/// navigation layer, so the bar keeps its glass.
struct ThreadScreenTitle: View {
    let roomName: String?
    /// The thread's reply count, or nil while the thread loads.
    let replyCount: Int?

    var body: some View {
        VStack(spacing: 0) {
            Text(ThreadPanelHeaderText.title)
                .font(.headline)
            if let subtitle = ThreadPanelHeaderText.subtitle(roomName: roomName, replyCount: replyCount) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The Follow control of the thread screen (MATRIX-261), in the navigation
/// bar: a bell, filled while the account follows the thread. The title names
/// the action, and the hint holds the help text of the Mac tooltip.
struct ThreadFollowButton: View {
    let model: ThreadFollowModel

    var body: some View {
        let control = model.control
        Button {
            Task { await model.toggle() }
        } label: {
            Label(control.title, systemImage: control.systemImage)
        }
        .disabled(!control.isEnabled)
        .accessibilityHint(control.help)
    }
}

extension View {
    /// Pushes the thread screen for `request` onto the navigation stack that
    /// shows this view (MATRIX-245). Nil pops it.
    ///
    /// The room screen is a destination of the iPhone stack, and the root of
    /// the iPad detail column's stack (`RoomNavigationShell`). So the thread
    /// screen covers the room on iPhone, and the room list stays beside it
    /// on iPad. The back button returns to the room, which keeps its
    /// timeline and scroll position.
    func threadDestination(
        _ request: Binding<ThreadScreenRequest?>,
        @ViewBuilder destination: @escaping (ThreadScreenRequest) -> some View
    ) -> some View {
        navigationDestination(item: request, destination: destination)
    }
}
