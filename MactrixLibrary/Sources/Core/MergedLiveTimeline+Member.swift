import Foundation
import MatrixRustSDK
import Models

extension MergedLiveTimeline {
    /// One member room of a merged timeline (MATRIX-142 Phase B): its
    /// timeline, and the merge's cached view of that timeline.
    @MainActor
    final class Member {
        let roomId: String
        let timeline: LiveTimeline
        /// The room whose room info names the room and its network.
        let labelRoom: SidebarRoom

        /// The member's items in SDK order, oldest first, as the merge reads
        /// them.
        private(set) var items: [MergedLiveItem] = []
        /// The same items by the SDK item's object identity. An SDK diff
        /// keeps the object of every item it does not touch, so an item read
        /// once is not read again.
        private var itemsByObject: [ObjectIdentifier: MergedLiveItem] = [:]
        /// The member reached the start of its room's history.
        var reachedStart = false
        /// The member is left out of the merge for good.
        private(set) var hasFailed = false
        var label: MergedSourceLabel
        var activity = MergedSendTarget.RoomActivity()

        init(roomId: String, timeline: LiveTimeline, labelRoom: SidebarRoom) {
            self.roomId = roomId
            self.timeline = timeline
            self.labelRoom = labelRoom
            label = MergedSourceLabel(roomId: roomId, network: nil, roomName: nil)
        }

        /// The source label: the room's network and what tells it from the
        /// other members (`MergedMemberIdentity`, MATRIX-147).
        func makeLabel(accounts: RoomAccountNames?) -> MergedSourceLabel {
            let identity = labelRoom.mergedMemberIdentity(accounts: accounts)
            return MergedSourceLabel(
                roomId: roomId,
                network: identity.network,
                roomName: identity.distinguishingName,
                account: accounts?.account(of: roomId, network: identity.network)
            )
        }

        /// Replaces `items` with the member timeline's current items.
        ///
        /// Cost: one dictionary lookup per item, plus one FFI read per item
        /// the cache has not seen. A new SDK object for a known item (a
        /// reaction, an edit, a send state) is a new item with a new
        /// revision, so the diff reloads its row.
        func updateItems(from source: [MatrixRustSDK.TimelineItem], nextRevision: inout Int) {
            var fresh: [ObjectIdentifier: MergedLiveItem] = [:]
            fresh.reserveCapacity(source.count)
            var mapped: [MergedLiveItem] = []
            mapped.reserveCapacity(source.count)
            for sdkItem in source {
                let key = ObjectIdentifier(sdkItem)
                let item: MergedLiveItem
                if let cached = itemsByObject[key] {
                    item = cached
                } else {
                    nextRevision += 1
                    item = MergedLiveItem(item: sdkItem, roomId: roomId, revision: nextRevision)
                }
                fresh[key] = item
                mapped.append(item)
            }
            items = mapped
            itemsByObject = fresh
        }

        /// Leaves the member out of the merge for good, and releases its
        /// items.
        func markFailed() {
            hasFailed = true
            items = []
            itemsByObject = [:]
        }
    }
}
