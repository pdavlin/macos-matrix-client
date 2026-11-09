import Foundation

/// Limits how many chat-list member loads run at one time (MATRIX-133).
///
/// A row that appears can start a member load (`SidebarRoom.loadChatListMembersIfNeeded`).
/// A fast scroll makes many rows appear, so the loads wait here for one of
/// `limit` slots. Waiters get a slot in the order they asked. A waiter whose
/// task was cancelled while it waited still gets its slot, and gives it back
/// at once without a load, so the cost of a skipped row is small.
actor ChatListMemberLoadGate {
    /// The app-wide gate: at most three member loads in flight.
    static let shared = ChatListMemberLoadGate(limit: 3)

    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    /// Waits for a free slot and takes it. Every call must be followed by
    /// one `release()`, also when the caller was cancelled.
    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            waiters.append(continuation)
        }
    }

    /// Hands the slot to the first waiter, or frees it when none waits.
    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
