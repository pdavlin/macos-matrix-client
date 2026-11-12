import Core
import Foundation
import MatrixRustSDK
import Models
import Observation
import OSLog
import SwiftUI
import UI

/// The composer state of one shown merged chat (MATRIX-143 Phase B).
///
/// The merged composer is the single-room `ChatInputView` with this session
/// beside it. The session decides which member room each message goes to,
/// and the composer makes the call on that member's `LiveTimeline`:
///
/// - A new message goes to the send target: Beeper's rule
///   (`MergedSendTarget.resolve`) over the merged timeline's `activity`,
///   the manual pick, and the time, kept still while the composer has
///   content (`MergedComposerTargeting`).
/// - A reply or an edit goes to the room of its event, for that message only
///   (`MergedChatRouting.composerTarget`). Rows ask their own member timeline
///   for a reply (`sendReplyTo`) or an edit (`pendingComposerEdit`); the
///   session watches every member for both.
/// - Typing notices go only to the current target
///   (`MergedChatRouting.composerTypingNotices`).
/// - The draft is one text per merged chat, in memory for the app session
///   (`MergedComposerDrafts`). No member room's SDK draft is read or written.
///
/// **Life.** One session per `MergedLiveTimeline`, made by `MergedChatView`
/// and dropped with it. So the manual pick lives per window and per merged
/// chat, and clears when the user leaves the merged chat (orchestrator
/// decision, MATRIX-143 Phase B). It is never persisted.
@MainActor @Observable
final class MergedComposerSession {
    /// The merged timeline whose member timelines the composer sends through.
    let timeline: MergedLiveTimeline

    /// The merged chat, kept current by `update(merge:)`: its name and its
    /// default room can change while it is shown.
    private(set) var merge: MergedChat

    /// The room the user picked in the target picker, or nil for the
    /// automatic choice.
    private(set) var manualPick: String?

    /// The new-message target and its memory.
    private(set) var targeting = MergedComposerTargeting()

    /// The member room of the message the composer edits, or nil.
    private(set) var editRoomId: String?

    /// The member room of the reply the user chose last, or nil.
    private(set) var replyRoomId: String?

    /// The drafts of every merged composer, for the app session.
    private static var drafts = MergedComposerDrafts()

    /// The chat list's room of each member, by room ID, read once: its
    /// loaded room info names the room and its network. Read once so a view
    /// that shows the names does not depend on the whole room list, which
    /// changes with every message in any room.
    @ObservationIgnored private let labelRooms: [String: SidebarRoom]
    @ObservationIgnored private var composerHasContent = false
    @ObservationIgnored private var isTyping = false
    @ObservationIgnored private var typingRoomId: String?

    /// - Parameters:
    ///   - timeline: The shown merged chat's timeline. Its member list is
    ///     fixed; a new member list needs a new timeline and a new session.
    ///   - merge: The merged chat as the account data holds it now.
    ///   - client: The signed-in client, for the member rooms' names and
    ///     networks.
    init(timeline: MergedLiveTimeline, merge: MergedChat, client: MatrixClient) {
        self.timeline = timeline
        self.merge = merge
        let memberRooms = Set(merge.rooms)
        var labelRooms: [String: SidebarRoom] = [:]
        for room in client.rooms where memberRooms.contains(room.id) {
            labelRooms[room.id] = room
        }
        self.labelRooms = labelRooms
        refresh()
        observeActivity()
        for member in members {
            observeReply(of: member)
            observeEditRequest(of: member)
        }
    }

    // MARK: - Members

    /// The member timelines, in member order.
    var members: [LiveTimeline] {
        timeline.actionTimelines
    }

    func member(_ roomId: String) -> LiveTimeline? {
        timeline.memberTimeline(for: roomId)
    }

    /// The merged chat without the member rooms that did not load
    /// (`MergedLiveTimeline.failedRoomIds`): a message can go only to a
    /// room whose timeline loaded.
    var sendableMerge: MergedChat {
        let failed = timeline.failedRoomIds
        guard !failed.isEmpty else { return merge }
        var sendable = merge
        sendable.rooms = merge.rooms.filter { !failed.contains($0) }
        return sendable
    }

    /// The target picker's options: each member room that loaded, in member
    /// order, with the room's display name and the chat list's network badge
    /// (`SidebarRoom.chatListPeople`).
    var targetOptions: [ComposerTargetOption] {
        sendableMerge.rooms.compactMap { roomId -> ComposerTargetOption? in
            guard let member = member(roomId) else { return nil }
            let sidebarRoom = labelRooms[roomId] ?? member.room.sidebarRoom
            let identity = sidebarRoom.mergedMemberIdentity(accounts: timeline.accounts)
            return ComposerTargetOption(
                id: roomId,
                name: identity.distinguishingName ?? (identity.network == nil ? roomId : ""),
                network: identity.network
            )
        }
    }

    // MARK: - Target

    /// What the composer writes now.
    var mode: MergedChatRouting.ComposerMode {
        MergedComposerTargeting.mode(editRoomId: editRoomId, replyRoomId: replyTimeline?.room.id)
    }

    /// The target of the composer's next message, with its reason.
    var composerTarget: MergedSendTarget? {
        targeting.target(for: mode, rooms: sendableMerge.rooms)
    }

    /// The member timeline the composer sends through now.
    var composerTimeline: LiveTimeline? {
        composerTarget.flatMap { member($0.roomId) }
    }

    /// Re-applies the send-target rule. Called on every input change, and
    /// once a minute by `MergedChatView`, because an old own message moves
    /// the target to the default room after 30 minutes.
    func refresh(now: Date = .now) {
        var next = targeting
        next.update(
            merge: sendableMerge,
            activity: timeline.activity,
            manualPick: manualPick,
            composerHasContent: composerHasContent,
            activityIsKnown: timeline.boundary != .pending,
            now: now
        )
        // Written only on a change, so the composer does not redraw for a
        // refresh that kept the target.
        if next != targeting {
            targeting = next
        }
        syncTyping()
    }

    /// Takes the newest version of the merged chat (name, default room).
    func update(merge: MergedChat) {
        guard merge != self.merge else { return }
        self.merge = merge
        refresh()
    }

    /// The target picker's choice: a member room, or nil for "Choose
    /// Automatically".
    func pick(_ roomId: String?) {
        Logger.mergedChatView.info("merged composer: manual pick \(roomId ?? "automatic", privacy: .public)")
        manualPick = roomId
        refresh()
    }

    /// Called by the composer when it gains or loses text or attachments.
    func composerContentDidChange(hasContent: Bool) {
        guard hasContent != composerHasContent else { return }
        composerHasContent = hasContent
        refresh()
    }

    /// Re-reads the activity whenever the merged timeline publishes it,
    /// whether every member loaded, or which members failed.
    private func observeActivity() {
        withObservationTracking {
            _ = timeline.activity
            _ = timeline.boundary
            _ = timeline.failedRoomIds
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.observeActivity()
            }
        }
    }

    // MARK: - Reply

    /// The member timeline that holds the reply, or nil. The member the user
    /// chose last wins; until the watch has caught up, any member with a
    /// reply counts, so the reply bar shows at once.
    var replyTimeline: LiveTimeline? {
        if let replyRoomId, let chosen = member(replyRoomId), chosen.sendReplyTo != nil {
            return chosen
        }
        return members.first { $0.sendReplyTo != nil }
    }

    /// The composer's reply, on the member timeline that holds it. Setting
    /// nil clears it; setting an item puts it on the member that holds the
    /// current reply (the composer only ever sets back the reply it had).
    var reply: Binding<MatrixRustSDK.EventTimelineItem?> {
        Binding(
            get: { [weak self] in self?.replyTimeline?.sendReplyTo },
            set: { [weak self] newValue in
                guard let self else { return }
                if newValue == nil {
                    for member in members where member.sendReplyTo != nil {
                        member.sendReplyTo = nil
                    }
                } else {
                    replyTimeline?.sendReplyTo = newValue
                }
            }
        )
    }

    /// Watches one member's reply. A new reply there becomes the composer's
    /// reply, and the other members' replies clear: the composer replies to
    /// one message at a time.
    private func observeReply(of member: LiveTimeline) {
        let roomId = member.room.id
        withObservationTracking {
            _ = member.sendReplyTo
        } onChange: { [weak self, weak member] in
            Task { @MainActor [weak self, weak member] in
                guard let self, let member else { return }
                replyDidChange(in: member, roomId: roomId)
                observeReply(of: member)
            }
        }
    }

    private func replyDidChange(in member: LiveTimeline, roomId: String) {
        if member.sendReplyTo != nil {
            replyRoomId = roomId
            for other in members where other !== member && other.sendReplyTo != nil {
                other.sendReplyTo = nil
            }
        } else if replyRoomId == roomId {
            replyRoomId = nil
        }
        syncTyping()
    }

    // MARK: - Edit

    /// The member timeline of the message the composer edits.
    var editTimeline: LiveTimeline? {
        editRoomId.flatMap(member)
    }

    /// Watches one member's edit request (a row's Edit action). The
    /// composer target moves to that member, and the composer, which reads
    /// `pendingComposerEdit` of its current timeline, starts the edit.
    private func observeEditRequest(of member: LiveTimeline) {
        let roomId = member.room.id
        withObservationTracking {
            _ = member.pendingComposerEdit
        } onChange: { [weak self, weak member] in
            Task { @MainActor [weak self, weak member] in
                guard let self, let member else { return }
                if member.pendingComposerEdit != nil {
                    editRoomId = roomId
                    syncTyping()
                }
                observeEditRequest(of: member)
            }
        }
    }

    /// Called by the composer when it starts to edit a message of `member`.
    func editDidBegin(in member: LiveTimeline) {
        editRoomId = member.room.id
        syncTyping()
    }

    /// Called by the composer when the edit ends: saved, cancelled, or left
    /// for a reply.
    func editDidEnd() {
        guard editRoomId != nil else { return }
        editRoomId = nil
        syncTyping()
    }

    /// The newest own message the composer can edit across the member rooms,
    /// for the Up arrow in an empty composer, with its member timeline.
    func lastEditTarget() -> (timeline: LiveTimeline, target: MessageEditTarget)? {
        var dates: [String: Date] = [:]
        var targets: [String: (timeline: LiveTimeline, target: MessageEditTarget)] = [:]
        for member in members {
            guard let candidate = member.newestEditCandidate() else { continue }
            dates[member.room.id] = candidate.date
            targets[member.room.id] = (member, candidate.target)
        }
        return MergedComposerTargeting.newestEditRoom(candidates: dates, rooms: merge.rooms).flatMap { targets[$0] }
    }

    // MARK: - Typing

    /// Called by the composer on every text change.
    func composerTextDidChange(isTyping: Bool) {
        self.isTyping = isTyping
        sendTypingNotices(MergedChatRouting.composerTypingNotices(
            previousRoom: typingRoomId,
            currentRoom: composerTarget?.roomId,
            isTyping: isTyping
        ))
    }

    /// Moves a running typing notice to a new target, or stops it. A no-op
    /// while the user does not type and no room shows them typing.
    private func syncTyping() {
        guard isTyping || typingRoomId != nil else { return }
        sendTypingNotices(MergedChatRouting.typingNotices(
            previousRoom: typingRoomId,
            currentRoom: composerTarget?.roomId,
            isTyping: isTyping
        ))
    }

    /// Stops the typing notice, for a merged chat that goes away.
    func stopTyping() {
        isTyping = false
        syncTyping()
    }

    private func sendTypingNotices(_ notices: [MergedChatRouting.TypingNotice]) {
        guard !notices.isEmpty else { return }
        typingRoomId = MergedChatRouting.typingRoom(after: notices, previousRoom: typingRoomId)
        let calls = notices.compactMap { notice -> (room: MatrixRustSDK.Room, isTyping: Bool)? in
            member(notice.roomId).map { ($0.room.room, notice.isTyping) }
        }
        Task {
            for call in calls {
                do {
                    try await call.room.typingNotice(isTyping: call.isTyping)
                } catch {
                    Logger.viewCycle.warning("Failed to send typing notice: \(error)")
                }
            }
        }
    }

    // MARK: - Draft and send

    /// The merged chat's draft text, "" when there is none.
    var draftText: String {
        Self.drafts.text(forMerge: merge.id)
    }

    /// Saves the draft in memory (`MergedComposerDrafts`).
    ///
    /// - Parameters:
    ///   - composerText: The composer text.
    ///   - textBeforeEdit: While the composer edits, the text from before
    ///     the edit.
    func saveDraft(composerText: String, textBeforeEdit: String?) {
        Self.drafts.save(composerText: composerText, textBeforeEdit: textBeforeEdit, forMerge: merge.id)
    }

    /// Scrolls the merged timeline to the newest row after a send. The
    /// member timeline's own request would go to no container.
    func requestScrollToBottom() {
        timeline.requestScrollToBottom()
    }

    /// The composer's placeholder: "Message <merged chat name>".
    var placeholder: String {
        String(localized: "Message \(merge.name)", comment: "The merged chat composer's placeholder, with the merged chat's name.")
    }
}

extension LiveTimeline {
    /// The newest own message the composer can edit, with its time.
    func newestEditCandidate() -> (target: MessageEditTarget, date: Date)? {
        for item in displayItems {
            if let event = item.asEvent(), let target = MessageEditTarget(event: event) {
                return (target, event.timestamp.date)
            }
        }
        return nil
    }
}
