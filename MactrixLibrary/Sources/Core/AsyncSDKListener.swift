import Foundation
import MatrixRustSDK
import OSLog

public final class AsyncSDKListener<Element: Sendable>: AsyncSequence, Sendable {
    public typealias Element = Element
    public typealias AsyncIterator = AsyncStream<Element>.Iterator

    private let stream: AsyncStream<Element>
    private let continuation: AsyncStream<Element>.Continuation

    public init() {
        let (s, c) = AsyncStream<Element>.makeStream()
        stream = s
        continuation = c
    }

    public func publishValue(_ element: Element) {
        continuation.yield(element)
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        return stream.makeAsyncIterator()
    }
}

extension AsyncSDKListener: TypingNotificationsListener where Element == [String] {
    public func call(typingUserIds: [String]) {
        publishValue(typingUserIds)
    }
}

extension AsyncSDKListener: RoomDirectorySearchEntriesListener where Element == [MatrixRustSDK.RoomDirectorySearchEntryUpdate] {
    public func onUpdate(roomEntriesUpdate: [MatrixRustSDK.RoomDirectorySearchEntryUpdate]) {
        publishValue(roomEntriesUpdate)
    }
}

extension AsyncSDKListener: SpaceRoomListPaginationStateListener where Element == MatrixRustSDK.SpaceRoomListPaginationState {
    public func onUpdate(paginationState: MatrixRustSDK.SpaceRoomListPaginationState) {
        publishValue(paginationState)
    }
}

extension AsyncSDKListener: SpaceRoomListEntriesListener where Element == [MatrixRustSDK.SpaceListUpdate] {
    public func onUpdate(rooms: [MatrixRustSDK.SpaceListUpdate]) {
        publishValue(rooms)
    }
}

extension AsyncSDKListener: SpaceRoomListSpaceListener where Element == MatrixRustSDK.SpaceRoom? {
    public func onUpdate(space: MatrixRustSDK.SpaceRoom?) {
        publishValue(space)
    }
}

extension AsyncSDKListener: SpaceServiceJoinedSpacesListener where Element == [MatrixRustSDK.SpaceListUpdate] {
    public func onUpdate(roomUpdates: [MatrixRustSDK.SpaceListUpdate]) {
        publishValue(roomUpdates)
    }
}

extension AsyncSDKListener: TimelineListener where Element == [MatrixRustSDK.TimelineDiff] {
    public func onUpdate(diff: [TimelineDiff]) {
        publishValue(diff)
    }
}

extension AsyncSDKListener: PaginationStatusListener where Element == MatrixRustSDK.PaginationStatus {
    public func onUpdate(status: MatrixRustSDK.PaginationStatus) {
        publishValue(status)
    }
}

extension AsyncSDKListener: RoomInfoListener where Element == MatrixRustSDK.RoomInfo {
    public func call(roomInfo: MatrixRustSDK.RoomInfo) {
        publishValue(roomInfo)
    }
}

extension AsyncSDKListener: RoomListEntriesListener where Element == [RoomListEntriesUpdate] {
    public func onUpdate(roomEntriesUpdate: [MatrixRustSDK.RoomListEntriesUpdate]) {
        publishValue(roomEntriesUpdate)
    }
}

// MARK: - Ordered state delivery (MATRIX-237)

@MainActor
public extension AsyncSDKListener {
    /// Applies each value on the main actor, one at a time, in the order the
    /// SDK sent them.
    ///
    /// MATRIX-237: one `Task { @MainActor in ... }` for each callback gives no
    /// order. A handler that suspends, or a task that starts late, lets an
    /// older value land after a newer one, and the newest value must win. The
    /// stream has one consumer, and the next value waits for `apply` to return.
    ///
    /// The task ends when it is cancelled.
    func deliver(to apply: @escaping @MainActor (Element) async -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            for await value in self {
                await apply(value)
            }
        }
    }
}

extension AsyncSDKListener: SyncServiceStateObserver where Element == MatrixRustSDK.SyncServiceState {
    public func onUpdate(state: MatrixRustSDK.SyncServiceState) {
        publishValue(state)
    }
}

extension AsyncSDKListener: RoomListServiceStateListener where Element == MatrixRustSDK.RoomListServiceState {
    public func onUpdate(state: MatrixRustSDK.RoomListServiceState) {
        publishValue(state)
    }
}

extension AsyncSDKListener: RoomListServiceSyncIndicatorListener where Element == MatrixRustSDK.RoomListServiceSyncIndicator {
    public func onUpdate(syncIndicator: MatrixRustSDK.RoomListServiceSyncIndicator) {
        publishValue(syncIndicator)
    }
}

extension AsyncSDKListener: VerificationStateListener where Element == MatrixRustSDK.VerificationState {
    public func onUpdate(status: MatrixRustSDK.VerificationState) {
        publishValue(status)
    }
}

extension AsyncSDKListener: RecoveryStateListener where Element == MatrixRustSDK.RecoveryState {
    public func onUpdate(status: MatrixRustSDK.RecoveryState) {
        publishValue(status)
    }
}

extension AsyncSDKListener: IgnoredUsersListener where Element == [String] {
    public func call(ignoredUserIds: [String]) {
        publishValue(ignoredUserIds)
    }
}

/// One callback of `SessionVerificationControllerDelegate`, as a value.
///
/// MATRIX-237: the callbacks are a sequence (request, data, finish), so they
/// go through one ordered stream. Out of order, a `finish` could clear the
/// emoji before the `data` that came before it sets them again.
public enum SessionVerificationEvent: Sendable {
    case receivedRequest(MatrixRustSDK.SessionVerificationRequestDetails)
    case acceptedRequest
    case startedSas
    case receivedData(MatrixRustSDK.SessionVerificationData)
    case failed
    case cancelled
    case finished
}

extension AsyncSDKListener: SessionVerificationControllerDelegate where Element == SessionVerificationEvent {
    public func didReceiveVerificationRequest(details: MatrixRustSDK.SessionVerificationRequestDetails) {
        publishValue(.receivedRequest(details))
    }

    public func didAcceptVerificationRequest() {
        publishValue(.acceptedRequest)
    }

    public func didStartSasVerification() {
        publishValue(.startedSas)
    }

    public func didReceiveVerificationData(data: MatrixRustSDK.SessionVerificationData) {
        publishValue(.receivedData(data))
    }

    public func didFail() {
        publishValue(.failed)
    }

    public func didCancel() {
        publishValue(.cancelled)
    }

    public func didFinish() {
        publishValue(.finished)
    }
}
