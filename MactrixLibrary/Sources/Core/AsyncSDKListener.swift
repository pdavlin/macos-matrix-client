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
