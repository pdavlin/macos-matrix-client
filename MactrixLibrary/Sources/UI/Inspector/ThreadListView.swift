import Models
import SwiftUI
import Tokens

/// The Threads pane of the inspector (MATRIX-200): one row per thread root
/// of the room, in the SDK's order, with a loading row, an end, an empty
/// state, and an error state with Retry.
///
/// The pane is the navigation layer, but the rows are list content: no
/// glass on them (hard rule 2).
public struct ThreadListView: View {
    let entries: [ThreadListEntry]
    let content: ThreadListPaneContent
    let pageRequestKey: Int
    let imageLoader: ImageLoader?
    let now: Date
    let onOpen: (String) -> Void
    let onLoadMore: () async -> Void
    let onRetry: () async -> Void

    /// - Parameters:
    ///   - entries: the rows, in the SDK's order.
    ///   - content: what the pane shows (`ThreadListPaneContent.of`).
    ///   - pageRequestKey: changes when a page request returns, so a loading
    ///     row still on screen asks for the next page.
    ///   - imageLoader: loads the avatars. Nil draws the initials.
    ///   - now: the time the row times are relative to.
    ///   - onOpen: opens the thread of a root event ID.
    ///   - onLoadMore: asks for the next page.
    ///   - onRetry: clears the error and asks for the page again.
    public init(
        entries: [ThreadListEntry],
        content: ThreadListPaneContent,
        pageRequestKey: Int = 0,
        imageLoader: ImageLoader?,
        now: Date = .now,
        onOpen: @escaping (String) -> Void,
        onLoadMore: @escaping () async -> Void,
        onRetry: @escaping () async -> Void
    ) {
        self.entries = entries
        self.content = content
        self.pageRequestKey = pageRequestKey
        self.imageLoader = imageLoader
        self.now = now
        self.onOpen = onOpen
        self.onLoadMore = onLoadMore
        self.onRetry = onRetry
    }

    public var body: some View {
        switch content {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task(id: pageRequestKey) { await onLoadMore() }
        case .empty:
            ContentUnavailableView(ThreadListPaneContent.emptyText, systemImage: "bubble.left.and.bubble.right")
        case let .failed(message):
            ContentUnavailableView {
                Label(ThreadListPaneContent.failedTitle, systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
                    .lineLimit(3)
            } actions: {
                Button("Retry") { Task { await onRetry() } }
            }
        case let .list(footer):
            list(footer: footer)
        }
    }

    private func list(footer: ThreadListFooter) -> some View {
        let prefetchStart = max(0, entries.count - ThreadToken.listPrefetchRows)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ThreadListRow(entry: entry, imageLoader: imageLoader, now: now) {
                        onOpen(entry.id)
                    }
                    .onAppear {
                        guard index >= prefetchStart, footer == .loading else { return }
                        Task { await onLoadMore() }
                    }
                    Divider()
                }
                footerView(footer)
            }
        }
    }

    @ViewBuilder
    private func footerView(_ footer: ThreadListFooter) -> some View {
        switch footer {
        case .loading:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ThreadToken.listRowVerticalPadding)
                .task(id: pageRequestKey) { await onLoadMore() }
        case let .failed(message):
            VStack(spacing: ThreadToken.listLineSpacing) {
                Text(ThreadListPaneContent.failedTitle)
                    .font(.system(size: ThreadToken.listMetaFontSize, weight: .semibold))
                Text(message)
                    .font(.system(size: ThreadToken.listMetaFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Retry") { Task { await onRetry() } }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ThreadToken.listRowVerticalPadding)
        case .end:
            EmptyView()
        }
    }
}

/// One row of the Threads pane (MATRIX-200): the root sender's avatar,
/// name, and the time of the last activity; a one-to-two line excerpt of the
/// root; the reply count and the latest reply.
public struct ThreadListRow: View {
    let entry: ThreadListEntry
    let imageLoader: ImageLoader?
    let now: Date
    let action: () -> Void

    @State private var isHovered = false

    public init(entry: ThreadListEntry, imageLoader: ImageLoader?, now: Date = .now, action: @escaping () -> Void) {
        self.entry = entry
        self.imageLoader = imageLoader
        self.now = now
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: ThreadToken.listAvatarTextSpacing) {
                AvatarImage(userProfile: entry.root.senderProfile, imageLoader: imageLoader)
                    .frame(width: ThreadToken.listAvatarSize, height: ThreadToken.listAvatarSize)
                    .clipShape(Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: ThreadToken.listLineSpacing) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.root.sender.name)
                            .font(.system(size: ThreadToken.listMetaFontSize, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: ThreadToken.listAvatarTextSpacing)
                        Text(ChatListTimestamp.text(for: entry.lastActivity, now: now))
                            .font(.system(size: ThreadToken.listMetaFontSize))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let excerpt = entry.root.excerpt {
                        Text(excerpt)
                            .font(.system(size: ThreadToken.listExcerptFontSize))
                            .lineLimit(ThreadToken.listRootLineLimit)
                            .multilineTextAlignment(.leading)
                    }
                    replyLine
                }
            }
            .padding(.vertical, ThreadToken.listRowVerticalPadding)
            .padding(.horizontal, ThreadToken.headerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(Color.accentColor.opacity(isHovered ? AccentToken.hoverBackgroundOpacity : 0))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Open Thread")
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the thread")
    }

    private var replyLine: some View {
        HStack(spacing: ThreadToken.chipContentSpacing) {
            Text(ThreadReplyCount.label(entry.replyCount))
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .fixedSize()
            if let latest = entry.latestReply?.prefixedExcerpt {
                Text(latest)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.system(size: ThreadToken.listReplyFontSize))
    }
}
