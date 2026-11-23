import MatrixRustSDK
import OSLog

extension LiveTimeline {
    /// Asks the SDK timeline to load the room's members, so it fills the
    /// sender profiles it has not resolved (MATRIX-163). Nothing made this
    /// call before: a profile that is unavailable when its item is built can
    /// stay that way in a room whose members load lazily, and the row then
    /// shows the user ID and initials. The SDK owns the fetch and the item
    /// updates; they arrive as normal timeline diffs.
    ///
    /// Each fetch is a "fetchMembers" signpost interval (MATRIX-182), so a
    /// measure can count the fetches of each room selection and find the
    /// diffs that arrive while one runs.
    func fetchMissingSenderProfiles() {
        guard let timeline else { return }
        let kind = focusedThreadId == nil ? "live" : "thread"
        Task(priority: .utility) { [signposts] in
            let fetch = signposts.beginMemberFetch(kind: kind)
            await timeline.fetchMembers()
            signposts.endMemberFetch(fetch)
        }
    }
}

/// The signposts of one `LiveTimeline` (MATRIX-182), in the "timeline-perf"
/// category of `OSSignposter.timeline`.
///
/// - "fetchMembers": an interval for each member fetch, with the number of
///   the timeline and its kind ("live" or "thread").
/// - "applyDiffs": an interval for each batch of timeline diffs on the main
///   actor, with the number of the timeline, the count of diffs, and whether
///   a member fetch of the timeline runs.
///
/// A number names the timeline in place of its room ID, so a recording holds
/// no room ID. Each new timeline of the process gets the next number.
@MainActor
final class TimelineSignposts {
    private static var lastNumber = 0

    private let number: Int
    private var memberFetchesRunning = 0
    private let signposter = OSSignposter.timeline

    init() {
        Self.lastNumber += 1
        number = Self.lastNumber
    }

    func beginMemberFetch(kind: String) -> OSSignpostIntervalState {
        memberFetchesRunning += 1
        return signposter.beginInterval(
            "fetchMembers",
            id: signposter.makeSignpostID(),
            "timeline \(self.number) \(kind, privacy: .public)"
        )
    }

    func endMemberFetch(_ state: OSSignpostIntervalState) {
        memberFetchesRunning -= 1
        signposter.endInterval("fetchMembers", state)
    }

    func beginDiffs(count: Int) -> OSSignpostIntervalState {
        signposter.beginInterval(
            "applyDiffs",
            id: signposter.makeSignpostID(),
            "timeline \(self.number) diffs \(count) fetchingMembers \(self.memberFetchesRunning > 0)"
        )
    }

    func endDiffs(_ state: OSSignpostIntervalState) {
        signposter.endInterval("applyDiffs", state)
    }
}
