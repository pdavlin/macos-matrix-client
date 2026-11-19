import Foundation
import MatrixRustSDK
import Models
import OSLog

/// The thread list of one room (MATRIX-200), over the SDK's
/// `ThreadListService`.
///
/// The SDK owns the list: it loads the pages, keeps each row current from
/// sync, and states every change as a `ThreadListUpdate`. This class only
/// replays those changes into `entries` and publishes the pagination state
/// (hard rule 1).
///
/// The Threads pane makes one for each room and calls `run()` from its
/// task. `run()` holds the service and its two subscriptions until the task
/// is cancelled (the room changes or the pane closes), then cancels the
/// subscriptions and releases the service.
@MainActor @Observable
public final class LiveThreadList {
    /// The rows, in the order the SDK gives.
    public private(set) var entries: [ThreadListEntry] = []
    /// The SDK's last pagination state.
    public private(set) var pagination: ThreadListPagination = .idle(endReached: false)
    /// The error of the last page request, or nil.
    public private(set) var errorMessage: String?

    /// What the pane shows.
    public var content: ThreadListPaneContent {
        ThreadListPaneContent.of(entryCount: entries.count, pagination: pagination, errorMessage: errorMessage)
    }

    @ObservationIgnored private let room: MatrixRustSDK.Room
    @ObservationIgnored private var service: ThreadListService?
    @ObservationIgnored private var isRequestingPage = false

    public init(room: MatrixRustSDK.Room) {
        self.room = room
    }

    /// Makes the service, subscribes to it, and loads the first page. Returns
    /// when the calling task is cancelled, after it cancels the
    /// subscriptions and releases the service.
    public func run() async {
        let service = room.threadListService()
        self.service = service

        let itemsListener = AsyncSDKListener<[ThreadListUpdate]>()
        let paginationListener = AsyncSDKListener<MatrixRustSDK.ThreadListPaginationState>()
        // The items subscription starts with a `reset` of the loaded rows.
        let itemsHandle = service.subscribeToItemsUpdates(listener: itemsListener)
        let paginationHandle = service.subscribeToPaginationStateUpdates(listener: paginationListener)
        pagination = service.paginationState().asModel

        let paginationTask = Task { [weak self] in
            for await state in paginationListener {
                guard let self else { return }
                self.pagination = state.asModel
            }
        }
        let firstPageTask = Task { [weak self] in
            await self?.loadNextPage()
        }
        defer {
            paginationTask.cancel()
            firstPageTask.cancel()
            itemsHandle.cancel()
            paginationHandle.cancel()
            self.service = nil
        }

        // The stream ends when the calling task is cancelled.
        for await updates in itemsListener {
            apply(updates)
        }
    }

    /// Counts the page requests that returned. The pane's loading row uses
    /// it as its task key, so a row still on screen after a page asks for
    /// the next one.
    public private(set) var finishedPageRequests = 0

    /// Asks the SDK for the next page. A no-op while a request of this list
    /// runs, after the last page, after a failure (until `retry()`), and
    /// when the service is gone. The SDK itself ignores a request while it
    /// loads.
    public func loadNextPage() async {
        guard let service, !isRequestingPage, errorMessage == nil, pagination != .idle(endReached: true) else { return }
        isRequestingPage = true
        defer {
            isRequestingPage = false
            finishedPageRequests += 1
        }
        do {
            try await service.paginate()
        } catch is CancellationError {
            return
        } catch {
            Logger.liveThreadList.error("thread list page failed: \(error, privacy: .public)")
            errorMessage = String(describing: error)
        }
    }

    /// Clears the error and asks for the page again.
    public func retry() async {
        errorMessage = nil
        await loadNextPage()
    }

    private func apply(_ updates: [ThreadListUpdate]) {
        for update in updates where !entries.apply(update.asModel) {
            // A change that does not fit: take the SDK's snapshot instead.
            Logger.liveThreadList.warning("thread list diff did not fit, taking a snapshot")
            entries = (service?.items() ?? []).map(ThreadListEntry.init)
            return
        }
    }
}

extension AsyncSDKListener: ThreadListEntriesListener where Element == [MatrixRustSDK.ThreadListUpdate] {
    public func onUpdate(diff: [MatrixRustSDK.ThreadListUpdate]) {
        publishValue(diff)
    }
}

extension AsyncSDKListener: ThreadListPaginationStateListener where Element == MatrixRustSDK.ThreadListPaginationState {
    public func onUpdate(state: MatrixRustSDK.ThreadListPaginationState) {
        publishValue(state)
    }
}

extension MatrixRustSDK.ThreadListPaginationState {
    var asModel: ThreadListPagination {
        switch self {
        case let .idle(endReached):
            .idle(endReached: endReached)
        case .loading:
            .loading
        }
    }
}

extension MatrixRustSDK.ThreadListUpdate {
    /// The same change, with the rows as app models.
    var asModel: ListDiff<ThreadListEntry> {
        let diff: ListDiff<ThreadListItem> = switch self {
        case let .append(values): .append(values)
        case .clear: .clear
        case let .pushFront(value): .pushFront(value)
        case let .pushBack(value): .pushBack(value)
        case .popFront: .popFront
        case .popBack: .popBack
        case let .insert(index, value): .insert(index: Int(index), value: value)
        case let .set(index, value): .set(index: Int(index), value: value)
        case let .remove(index): .remove(index: Int(index))
        case let .truncate(length): .truncate(length: Int(length))
        case let .reset(values): .reset(values)
        }
        return diff.map(ThreadListEntry.init)
    }
}

extension ThreadListEntry {
    init(_ item: MatrixRustSDK.ThreadListItem) {
        self.init(
            root: ThreadListMessage(item.rootEvent),
            latestReply: item.latestEvent.map(ThreadListMessage.init),
            replyCount: Int(item.numReplies)
        )
    }
}

extension ThreadListMessage {
    init(_ event: MatrixRustSDK.ThreadListItemEvent) {
        var displayName: String?
        var avatarUrl: String?
        if case let .ready(displayName: name, displayNameAmbiguous: _, avatarUrl: url) = event.senderProfile {
            displayName = name
            avatarUrl = url
        }
        self.init(
            eventId: event.eventId,
            sender: ChatListSender(userId: event.sender, displayName: displayName, isOwn: event.isOwn),
            avatarUrl: avatarUrl,
            date: MatrixRustSDK.LatestEventValue.date(event.timestamp),
            content: event.content?.chatListContent
        )
    }
}
