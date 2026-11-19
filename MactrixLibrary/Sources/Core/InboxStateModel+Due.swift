#if os(macOS)
    import AppKit
#endif
import Foundation
import MatrixRustSDK
import Models
import Observation
import OSLog

// MATRIX-207: the due times of Snooze and Remind me later. One timer waits
// for the next snooze end or reminder (`InboxStateDocument.nextDueDate`).
// It is armed again when the inbox states change and when the Mac wakes
// from sleep. The first arm resolves every item that came due while the app
// was closed.

public extension InboxStateModel {
    /// Starts the due timer.
    ///
    /// - Parameter notify: posts a local notification: a title, a body, and
    ///   the room a click opens.
    func startDueTimer(notify: @escaping @MainActor (_ title: String, _ body: String, _ roomId: String) -> Void) {
        dueNotify = notify
        #if os(macOS)
            if wakeObserver == nil {
                wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.armDueTimer()
                    }
                }
            }
        #endif
        armDueTimer()
    }

    /// Stops the due timer (sign-out).
    func stopDueTimer() {
        dueGeneration += 1
        dueTimer?.cancel()
        dueTimer = nil
        dueNotify = nil
        #if os(macOS)
            if let wakeObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            }
        #endif
        wakeObserver = nil
    }
}

extension InboxStateModel {
    /// Arms the timer for the next due time. Reads the document inside
    /// Observation tracking, so a change arms it again.
    func armDueTimer() {
        guard dueNotify != nil else { return }
        dueGeneration += 1
        let generation = dueGeneration
        dueTimer?.cancel()
        let next = withObservationTracking {
            document.nextDueDate
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, generation == self.dueGeneration else { return }
                self.armDueTimer()
            }
        }
        guard let next else {
            dueTimer = nil
            return
        }
        dueTimer = Task { [weak self] in
            let delay = next.timeIntervalSinceNow
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            await self?.resolveDue(now: .now)
        }
    }

    /// Fires what came due at `now`.
    ///
    /// 1. The activity rule runs first on the due chats: a reply that came
    ///    while the app was closed drops a reminder, and a message from
    ///    another person ends a snooze early.
    /// 2. The still-due fields are cleared in one write.
    /// 3. Each chat whose write landed is marked unread through the SDK
    ///    (`Room.setUnreadFlag`) and gets one local notification.
    func resolveDue(now: Date) async {
        guard isEditable else { return }
        let candidates = document.dueChats(at: now, merges: merges)
        guard !candidates.isEmpty else { return }
        await checkActivity(roomIds: candidates.flatMap(\.roomIds))

        let due = document.dueChats(at: now, merges: merges)
        guard !due.isEmpty else { return }
        await mutate { $0.resolve(due, at: now) }.value

        let stillDue = Set(document.dueChats(at: now, merges: merges).map(\.id))
        for chat in due where !stillDue.contains(chat.id) {
            await markUnread(roomIds: chat.roomIds)
            let message = chat.notification(chatName: chat.mergedChatName ?? roomName(chat.defaultRoomId))
            Logger.inbox.info("due: \(chat.reminderFired ? "reminder" : "snooze end", privacy: .public) for \(chat.id, privacy: .public)")
            dueNotify?(message.title, message.body, chat.defaultRoomId)
        }
    }

    /// Sets the SDK's marked-unread flag on each room. A failure is logged
    /// and the other rooms still change.
    private func markUnread(roomIds: [String]) async {
        for roomId in roomIds {
            do {
                guard let room = try sdkClient.getRoom(roomId: roomId) else { continue }
                try await room.setUnreadFlag(newValue: true)
            } catch {
                Logger.inbox.error("failed to mark \(roomId, privacy: .public) unread: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The room's display name, or "a chat" when the client does not know it.
    private func roomName(_ roomId: String) -> String {
        ((try? sdkClient.getRoom(roomId: roomId)) ?? nil)?.displayName() ?? "a chat"
    }
}
