import Foundation
import MatrixRustSDK
import Models
import OSLog

// MATRIX-142 Phase B: the API the merged timeline container (Wave 2) calls.
// Every call goes to member rooms through their own `LiveTimeline`.

// MARK: - Routing

public extension MergedLiveTimeline {
    /// The member timeline of `roomId`, or nil when the room is not a member
    /// or was left out. Actions, sends, edits, and reactions on that room's
    /// events go through it (`MergedChatRouting`).
    func memberTimeline(for roomId: String) -> LiveTimeline? {
        member(roomId)?.timeline
    }

    /// The member room of an item row or a source note row, or nil for the
    /// rows of the whole merged chat (date dividers, the read marker, the
    /// timeline start).
    func roomId(ofRowId rowId: String) -> String? {
        MergedTimelineEntryID.roomId(ofRowId: rowId, among: merge.rooms)
    }

    /// The member timeline that holds the row's event, or nil for a row of
    /// the whole merged chat. Pass it to the row view as its timeline.
    func memberTimeline(forRowId rowId: String) -> LiveTimeline? {
        roomId(ofRowId: rowId).flatMap(memberTimeline(for:))
    }

    /// The merged row identifier of an event of a member room, or nil when
    /// the member has not loaded the event. The row may still be hidden by
    /// the boundary; the container checks that it holds the identifier.
    ///
    /// Cost: one pass over the member's loaded items, no FFI.
    func rowId(ofEvent eventId: MatrixRustSDK.EventOrTransactionId, inRoom roomId: String) -> String? {
        guard let item = member(roomId)?.items.first(where: { $0.eventOrTransactionId == eventId }) else { return nil }
        return MergedTimelineEntryID.item(roomId: roomId, itemId: item.mergedItemId)
    }

    /// Asks the container to scroll to an event of a member room.
    func focusEvent(_ eventId: MatrixRustSDK.EventOrTransactionId, inRoom roomId: String) {
        Logger.mergedChats.info("merged timeline: focus event \(eventId.id) in \(roomId, privacy: .public)")
        focusedEvent = MergedFocusedEvent(roomId: roomId, eventId: eventId)
    }
}

// MARK: - Pagination

public extension MergedLiveTimeline {
    /// Back-paginates the member rooms that hold the boundary, at the same
    /// time (`MergedTimelineMerger.paginationTargets`). Paginating another
    /// member would reveal nothing: its older events stay hidden behind the
    /// boundary. Each member uses its own `fetchOlderMessages()`, so a member
    /// that already paginates, or whose last pagination failed, is skipped.
    func paginateBackwards() async {
        let timelines = paginationTargets.compactMap(memberTimeline(for:))
        guard !timelines.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for timeline in timelines {
                group.addTask {
                    await timeline.fetchOlderMessages()
                }
            }
        }
    }

    /// True while a member that is not left out back-paginates.
    var isPaginating: Bool {
        liveMembers.contains { member in
            if case .paginating = member.timeline.paginating { return true }
            return false
        }
    }

    /// The failure of the first member whose last back-pagination failed, or
    /// nil.
    var paginationFailure: String? {
        liveMembers.lazy.compactMap(\.timeline.paginationFailure).first
    }

    /// Retries the back-pagination of every member whose last one failed.
    func retryPagination() {
        for member in liveMembers where member.timeline.paginationFailure != nil {
            member.timeline.retryPagination()
        }
    }
}

// MARK: - Typing and scroll

public extension MergedLiveTimeline {
    /// The users who type in any member room, in member order, each once.
    var typingUserIds: [String] {
        var seen = Set<String>()
        return liveMembers.flatMap(\.timeline.room.typingUserIds).filter { seen.insert($0).inserted }
    }

    /// The display names of the users in `typingUserIds`, read from the
    /// member list of the room they type in, else their user IDs.
    var typingNames: [String] {
        var seen = Set<String>()
        var names: [String] = []
        for member in liveMembers {
            let room = member.timeline.room
            for userId in room.typingUserIds where seen.insert(userId).inserted {
                names.append(room.members.first { $0.userId == userId }?.displayName ?? userId)
            }
        }
        return names
    }

    /// Messages from others that arrived in any member room while the view
    /// was away from the newest rows.
    var unseenArrivals: Int {
        liveMembers.reduce(0) { $0 + $1.timeline.unseenArrivals }
    }

    /// Called by the container as the scroll position crosses the bottom
    /// threshold. Every member timeline gets the same state, so each one
    /// counts and clears its unseen arrivals.
    func setAtBottom(_ atBottom: Bool) {
        if isAtBottom != atBottom {
            isAtBottom = atBottom
        }
        for member in members {
            member.timeline.setAtBottom(atBottom)
        }
    }

    /// Asks the container to scroll to the newest row.
    func requestScrollToBottom() {
        scrollToBottomRequests += 1
        setAtBottom(true)
    }
}

// MARK: - Read receipts

public extension MergedLiveTimeline {
    /// Tells the model which row is the newest visible one. Call it when the
    /// scroll position or the rows change while the window is active.
    ///
    /// After `receiptDelay` it maps the newest row it was told to the newest
    /// visible event of each member room (`MergedReadReceiptMapping`) and
    /// sends one receipt per room whose receipt moves forward
    /// (`MergedChatRouting.readReceipts`), through that room's timeline.
    ///
    /// - Parameter rowId: the identifier of the newest visible row.
    func noteNewestVisibleRow(id rowId: String) {
        pendingNewestVisibleRowId = rowId
        guard receiptTask == nil else { return }
        let delay = receiptDelay
        receiptTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.sendPendingReadReceipts()
        }
    }

    /// Marks every member room as read, through each room's existing
    /// `Timeline.markAsRead(receiptType:)` call. The single-room view sends
    /// `.fullyRead` this way when it closes.
    func markMembersAsRead(receiptType: ReceiptType) async {
        let timelines = liveMembers.compactMap { member -> (roomId: String, timeline: Timeline)? in
            member.timeline.timeline.map { (member.roomId, $0) }
        }
        await withTaskGroup(of: Void.self) { group in
            for (roomId, timeline) in timelines {
                group.addTask {
                    do {
                        try await timeline.markAsRead(receiptType: receiptType)
                    } catch {
                        let reason = String(describing: error)
                        Logger.mergedChats.error(
                            "merged timeline: failed to mark \(roomId, privacy: .public) read: \(reason, privacy: .public)"
                        )
                    }
                }
            }
        }
    }
}

extension MergedLiveTimeline {
    /// Sends the receipts for the newest visible row the container named
    /// last. Each receipt counts as sent at once, so a second call does not
    /// repeat it; a failed one is forgotten so a later call retries it.
    func sendPendingReadReceipts() {
        receiptTask = nil
        guard let rowId = pendingNewestVisibleRowId else { return }
        pendingNewestVisibleRowId = nil
        guard let index = displayRows.firstIndex(where: { $0.id == rowId }) else { return }

        let rooms = liveMembers.map(\.roomId)
        let candidates = MergedReadReceiptMapping.newestVisibleEvents(in: displayRows, newestVisibleIndex: index, rooms: rooms)
        let receipts = MergedChatRouting.readReceipts(
            newestVisibleEvents: MergedReadReceiptMapping.advancing(candidates, past: lastSentReceipts),
            alreadySent: lastSentReceipts.mapValues(\.eventId),
            rooms: rooms
        )
        for receipt in receipts {
            guard let timeline = memberTimeline(for: receipt.roomId), let candidate = candidates[receipt.roomId] else { continue }
            let roomId = receipt.roomId
            let previous = lastSentReceipts[roomId]
            lastSentReceipts[roomId] = candidate
            Task { @MainActor [weak self] in
                let sent = await timeline.sendReadReceipt(eventId: candidate.eventId)
                // Keep a newer receipt that was sent in the meantime.
                if !sent, let self, self.lastSentReceipts[roomId] == candidate {
                    self.lastSentReceipts[roomId] = previous
                }
            }
        }
    }
}
