import Foundation
import MatrixRustSDK
import Models
import Observation
import OSLog

/// The live timeline of a merged chat (MATRIX-142 Phase B, contract §4 M2.5):
/// one `LiveTimeline` per member room, merged into one row list.
///
/// Presentation only (contract §11, 2026-11-10). Every SDK call goes to one
/// member room through that room's own `LiveTimeline`: loading, paginating,
/// sending, reacting, editing, and read receipts. This model only reorders
/// and decorates what the member timelines already hold, with the merge
/// engine (`MergedTimelineMerger`) and the row builder
/// (`MergedTimelineRowBuilder`).
///
/// **For the timeline container (Wave 2).** The model is a row source in the
/// shape the container reads from `LiveTimeline`:
///
/// - `rows` is the display order, newest first, like
///   `LiveTimeline.displayItems.map(\.row)`. Rows are grouped (MATRIX-68).
///   Row identifiers are the merged entry identifiers
///   (`MergedTimelineEntryID`), never the SDK's.
/// - `drainRowChanges()` hands over the changes since the last drain, like
///   `LiveTimeline.drainDisplayChanges()`, but with rows instead of SDK
///   items, because date dividers and source notes have no SDK item.
/// - A row's member room: `roomId(ofRowId:)`, and its timeline:
///   `memberTimeline(forRowId:)`. Give each row view the member timeline of
///   its own room, so every action on a message (reply, reaction, edit,
///   redaction, forward, the reaction picker) goes to the room that holds
///   the event (`MergedChatRouting.route`).
/// - Back-pagination: `paginateBackwards()`, with `isPaginating`,
///   `paginationFailure`, and `retryPagination()` for the oldest-end row.
/// - Read receipts: `noteNewestVisibleRow(id:)`.
///
/// The API for those lives in `MergedLiveTimeline+Routing.swift`. This file
/// holds the state and the recompute.
///
/// **Life.** One instance per opened merged chat. It does not follow edits
/// of the merged chat: when its member rooms change, make a new instance.
@MainActor @Observable
public final class MergedLiveTimeline {
    /// The merged chat this timeline shows.
    public let merge: MergedChat

    /// The calendar the merge and the sender grouping use. It decides where
    /// a day starts, so it must be the container's grouping calendar.
    public let calendar: Calendar

    /// The merged rows, newest first: the container's display order.
    public private(set) var rows: [TimelineRow] = []

    /// The newest message times per member room ID, for the composer's send
    /// target (`MergedSendTarget.resolve(for:activity:manualPick:now:)`).
    public private(set) var activity: [String: MergedSendTarget.RoomActivity] = [:]

    /// The boundary the merge applied at the oldest end.
    public private(set) var boundary: MergedTimelineBoundary = .pending

    /// The member rooms that `paginateBackwards()` paginates next.
    public private(set) var paginationTargets: [String] = []

    /// The member rooms left out of the merge, in member order: the client
    /// does not know the room, or its timeline failed to load. Each failure
    /// is logged once.
    public private(set) var failedRoomIds: [String] = []

    /// The event to scroll to, set by `focusEvent(_:inRoom:)`, and by a
    /// member timeline's own focus request (a reply jump in a row), which
    /// the model forwards here. The container resolves it with
    /// `rowId(ofEvent:inRoom:)` after each update, as it resolves
    /// `LiveTimeline.focusedTimelineEventId`.
    public internal(set) var focusedEvent: MergedFocusedEvent?

    /// Whether the view shows the newest rows. See `setAtBottom(_:)`.
    public internal(set) var isAtBottom = true

    /// A counter the container observes; each increment asks it to scroll to
    /// the newest row.
    public internal(set) var scrollToBottomRequests = 0

    /// How long `noteNewestVisibleRow(id:)` waits before it sends receipts,
    /// so a scroll sends one batch, not one per row. The single-room view
    /// waits the same second before it marks the room read.
    public let receiptDelay: Duration

    /// The member rooms that have a timeline, in member order.
    let members: [Member]
    /// The published rows with their routing data, newest first.
    @ObservationIgnored private(set) var displayRows: [MergedDisplayRow] = []
    @ObservationIgnored var lastSentReceipts: [String: MergedReceiptCandidate] = [:]
    @ObservationIgnored var pendingNewestVisibleRowId: String?
    @ObservationIgnored var receiptTask: Task<Void, Never>?
    @ObservationIgnored private var pendingRowChanges: [TimelineRowDisplayUpdate] = []
    @ObservationIgnored private var coalescer = MergedRecomputeCoalescer()
    @ObservationIgnored private var nextRevision = 0
    @ObservationIgnored private var unresolvedRoomIds: [String]

    /// Opens one timeline per member room.
    ///
    /// Each room comes from the sidebar's room list, else from
    /// `Client.getRoom(roomId:)`: the lookup `MainView.onRoomSelected` uses.
    /// A room the client does not know is left out and logged. Each member
    /// timeline is a new `LiveTimeline(room: LiveRoom(matrixRoom:))`, as for a
    /// single room. Do not show those timelines elsewhere: this model drains
    /// their display-change queues.
    ///
    /// - Parameters:
    ///   - client: the signed-in client.
    ///   - merge: the merged chat to show.
    ///   - calendar: the container's grouping calendar.
    ///   - receiptDelay: see `receiptDelay`.
    public convenience init(
        client: MatrixClient,
        merge: MergedChat,
        calendar: Calendar = .autoupdatingCurrent,
        receiptDelay: Duration = .seconds(1)
    ) {
        var timelines: [LiveTimeline] = []
        var labelRooms: [String: SidebarRoom] = [:]
        for roomId in Self.uniqueRooms(of: merge) {
            let sidebarRoom = client.rooms.first { $0.id == roomId }
            guard let room = sidebarRoom?.room ?? Self.clientRoom(roomId, of: client) else { continue }
            timelines.append(LiveTimeline(room: LiveRoom(matrixRoom: room)))
            labelRooms[roomId] = sidebarRoom
        }
        self.init(merge: merge, timelines: timelines, labelRooms: labelRooms, calendar: calendar, receiptDelay: receiptDelay)
    }

    /// Merges the given member timelines.
    ///
    /// - Parameters:
    ///   - merge: the merged chat.
    ///   - timelines: one live (not thread) timeline per member room. A
    ///     timeline of a room that is not a member, or a second one of a
    ///     room, is ignored. A member room without a timeline is left out.
    ///   - labelRooms: the sidebar room per room ID whose loaded room info
    ///     names the room and its network in the source note. A missing room
    ///     uses the timeline's own room.
    ///   - calendar: the container's grouping calendar.
    ///   - receiptDelay: see `receiptDelay`.
    init(
        merge: MergedChat,
        timelines: [LiveTimeline],
        labelRooms: [String: SidebarRoom],
        calendar: Calendar,
        receiptDelay: Duration
    ) {
        self.merge = merge
        self.calendar = calendar
        self.receiptDelay = receiptDelay

        var members: [Member] = []
        var unresolved: [String] = []
        for roomId in Self.uniqueRooms(of: merge) {
            guard let timeline = timelines.first(where: { $0.room.id == roomId && $0.focusedThreadId == nil }) else {
                Logger.mergedChats.error("merged timeline: member room \(roomId, privacy: .public) is left out: no room")
                unresolved.append(roomId)
                continue
            }
            let labelRoom = labelRooms[roomId] ?? timeline.room.sidebarRoom
            members.append(Member(roomId: roomId, timeline: timeline, labelRoom: labelRoom))
        }
        self.members = members
        unresolvedRoomIds = unresolved
        failedRoomIds = unresolved

        for member in members {
            observe(member)
            observeFocus(of: member)
            scheduleRecompute(of: member.roomId)
        }
    }

    /// The SDK room the client's store holds for `roomId`, or nil.
    private static func clientRoom(_ roomId: String, of client: MatrixClient) -> MatrixRustSDK.Room? {
        guard let sdkClient: ClientProtocol = client.client else { return nil }
        do {
            return try sdkClient.getRoom(roomId: roomId)
        } catch {
            Logger.mergedChats.error("merged timeline: no room \(roomId, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func uniqueRooms(of merge: MergedChat) -> [String] {
        var seen = Set<String>()
        return merge.rooms.filter { seen.insert($0).inserted }
    }

    // MARK: - Rows

    /// Hands the container every row change since its last call, and clears
    /// the queue. The changes apply in order to the rows of the previous
    /// drain (`TimelineRowDiff` states the order). A container that has never
    /// drained starts from `rows` and drains once before its first update,
    /// as with `LiveTimeline.drainDisplayChanges()`.
    public func drainRowChanges() -> [TimelineRowDisplayUpdate] {
        defer { pendingRowChanges.removeAll(keepingCapacity: true) }
        return pendingRowChanges
    }

    /// Drops queued changes and makes the next drain a reset.
    public func invalidateRowChanges() {
        pendingRowChanges = [TimelineRowDisplayUpdate(change: .reset)]
    }

    /// Recomputes the whole merge on the next turn, for example after a time
    /// zone change, which moves the day boundaries.
    public func recomputeAll() {
        for member in members {
            scheduleRecompute(of: member.roomId)
        }
    }

    // MARK: - Recompute

    /// The members that are not left out, in member order.
    var liveMembers: [Member] {
        members.filter { !$0.hasFailed }
    }

    func member(_ roomId: String) -> Member? {
        members.first { $0.roomId == roomId }
    }

    /// Watches what the merge reads from one member: its items, its
    /// pagination status, its load failure, and its room info (the source
    /// label). One change schedules one recompute; the watch re-arms then.
    private func observe(_ member: Member) {
        let roomId = member.roomId
        withObservationTracking {
            _ = member.timeline.timelineItems
            _ = member.timeline.paginating
            _ = member.timeline.errorMessage
            _ = member.labelRoom.roomInfo
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.memberDidChange(roomId)
            }
        }
    }

    private func memberDidChange(_ roomId: String) {
        guard let member = member(roomId), !member.hasFailed else { return }
        observe(member)
        scheduleRecompute(of: roomId)
    }

    /// Watches one member's focused event (MATRIX-142 Wave 2). A row asks
    /// its own member timeline to focus an event, for example the reply
    /// jump in `ChatMessageView`; the container reads only `focusedEvent`,
    /// so the member's request is forwarded there with the member's room.
    private func observeFocus(of member: Member) {
        let roomId = member.roomId
        withObservationTracking {
            _ = member.timeline.focusedTimelineEventId
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.memberFocusDidChange(roomId)
            }
        }
    }

    private func memberFocusDidChange(_ roomId: String) {
        guard let member = member(roomId) else { return }
        observeFocus(of: member)
        guard let eventId = member.timeline.focusedTimelineEventId else { return }
        focusEvent(eventId, inRoom: roomId)
    }

    /// Marks a member changed, and schedules one recompute for every change
    /// up to it (the engine's coalescing rule).
    private func scheduleRecompute(of roomId: String) {
        guard coalescer.markDirty(roomId) else { return }
        Task { @MainActor [weak self] in
            self?.flush()
        }
    }

    private func flush() {
        let dirty = coalescer.beginFlush()
        for member in members where dirty.contains(member.roomId) {
            refresh(member)
        }
        recompute()
    }

    /// Re-reads one member after a change. Only the SDK items it has not
    /// seen are read across the FFI.
    private func refresh(_ member: Member) {
        let timeline = member.timeline
        if timeline.timeline == nil, let error = timeline.errorMessage {
            if !member.hasFailed {
                Logger.mergedChats.error(
                    "merged timeline: member room \(member.roomId, privacy: .public) is left out: \(error, privacy: .public)"
                )
                member.markFailed()
            }
            return
        }
        member.reachedStart = timeline.paginating == .idle(hitTimelineStart: true)
        member.label = member.makeLabel()
        member.updateItems(from: timeline.timelineItems, nextRevision: &nextRevision)
        member.activity = MergedSendTarget.RoomActivity(newestFirst: member.items.reversed().lazy.map(\.messageActivity))
        // No container drains a member's display queue, so it would grow for
        // the life of the merged chat.
        _ = timeline.drainDisplayChanges()
    }

    /// Merges the members, builds the rows, diffs them against the previous
    /// rows, and publishes what changed. One run per coalesced batch.
    private func recompute() {
        let started = ContinuousClock.now
        let live = liveMembers
        let input = live.map { member in
            MergedTimelineMember(roomId: member.roomId, items: member.items, reachedStart: member.reachedStart)
        }
        let content = MergedTimelineMerger.merge(input, calendar: calendar)
        var labels: [String: MergedSourceLabel] = [:]
        for member in live {
            labels[member.roomId] = member.label
        }
        let built = MergedTimelineRowBuilder.displayRows(from: content, labels: labels, calendar: calendar)
        let unique = TimelineRowIdentity.removingDuplicates(built) { (row: MergedDisplayRow) -> String in row.id }
        if !unique.removedIds.isEmpty {
            Logger.mergedChats.error("merged timeline repeats \(unique.removedIds.count) row identity(ies), dropped")
        }

        let updates = MergedTimelineRowBuilder.updates(from: displayRows, to: unique.unique)
        displayRows = unique.unique
        if !updates.isEmpty {
            for update in updates {
                TimelineDisplayChangeQueue.enqueue(update, into: &pendingRowChanges) { (queued: TimelineRowDisplayUpdate) in
                    queued.change
                }
            }
            rows = displayRows.map(\.row)
        }
        publishDerivedState(content: content, input: input, live: live)

        let elapsed = (ContinuousClock.now - started).components
        let milliseconds = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
        Logger.mergedChats.debug(
            "merged timeline recompute: \(self.displayRows.count) row(s), \(updates.count) change(s), \(milliseconds) ms"
        )
    }

    /// Writes the boundary, the pagination targets, the activity, and the
    /// left-out rooms, each only when it changed, so observers of one do not
    /// wake for a recompute that left it alone.
    private func publishDerivedState(
        content: MergedTimelineContent<MergedLiveItem>,
        input: [MergedTimelineMember<MergedLiveItem>],
        live: [Member]
    ) {
        if boundary != content.boundary {
            boundary = content.boundary
        }
        let targets = MergedTimelineMerger.paginationTargets(of: input)
        if targets != paginationTargets {
            paginationTargets = targets
        }
        var newActivity: [String: MergedSendTarget.RoomActivity] = [:]
        for member in live {
            newActivity[member.roomId] = member.activity
        }
        if newActivity != activity {
            activity = newActivity
        }
        let failed = Set(unresolvedRoomIds + members.filter(\.hasFailed).map(\.roomId))
        let orderedFailed = merge.rooms.filter { failed.contains($0) }
        if orderedFailed != failedRoomIds {
            failedRoomIds = orderedFailed
        }
    }
}

/// An event of a member room that the merged timeline should scroll to.
public struct MergedFocusedEvent: Equatable {
    public let roomId: String
    public let eventId: MatrixRustSDK.EventOrTransactionId

    public init(roomId: String, eventId: MatrixRustSDK.EventOrTransactionId) {
        self.roomId = roomId
        self.eventId = eventId
    }
}
