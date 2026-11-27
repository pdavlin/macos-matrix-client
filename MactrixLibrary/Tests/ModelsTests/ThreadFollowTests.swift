import Foundation
import Models
import Testing

/// MATRIX-261: the pure rules of thread follow.
struct ThreadFollowTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: Control

    @Test func readingShowsFollowDisabled() {
        let control = ThreadFollowControl(state: .reading)
        #expect(control.title == "Follow Thread")
        #expect(control.systemImage == "bell")
        #expect(!control.isEnabled)
        #expect(!control.isFollowed)
    }

    @Test func notFollowedOffersFollow() {
        let control = ThreadFollowControl(state: .notFollowed)
        #expect(control.title == "Follow Thread")
        #expect(control.systemImage == "bell")
        #expect(control.isEnabled)
        #expect(control.follows)
        #expect(control.help == ThreadFollowControl.followHelp)
    }

    /// The tooltip carries the #6735 limit in one sentence.
    @Test func followedOffersUnfollowWithTheLimit() {
        let control = ThreadFollowControl(state: .followed)
        #expect(control.title == "Unfollow Thread")
        #expect(control.systemImage == "bell.fill")
        #expect(control.isEnabled)
        #expect(control.isFollowed)
        #expect(!control.follows)
        #expect(control.help.contains("In All Messages rooms and DMs, the next reply follows it again."))
    }

    /// A change on its way shows the target state, disabled.
    @Test(arguments: [true, false])
    func changingShowsTheTargetDisabled(toFollowed: Bool) {
        let control = ThreadFollowControl(state: .changing(toFollowed: toFollowed))
        #expect(control.isFollowed == toFollowed)
        #expect(!control.isEnabled)
    }

    /// Before MSC4306 the read is nil, so the control shows off. A failed
    /// read shows off too, with no alert.
    @Test func readMapsToState() {
        #expect(ThreadFollowState(read: .notRead) == .reading)
        #expect(ThreadFollowState(read: .followed) == .followed)
        #expect(ThreadFollowState(read: .notFollowed) == .notFollowed)
        #expect(ThreadFollowState(read: .failed) == .notFollowed)
    }

    // MARK: Banner filter

    @Test(arguments: [ThreadSubscriptionSupport.unknown, .unsupported])
    func serverWithoutMSC4306KeepsEveryBanner(support: ThreadSubscriptionSupport) {
        for read in [ThreadFollowRead.notRead, .notFollowed, .followed, .failed] {
            let decision = ThreadBannerRule.decide(threadRoot: "$root", hasMention: false, support: support, read: read)
            #expect(decision == .show)
        }
    }

    @Test func eventInNoThreadShows() {
        let decision = ThreadBannerRule.decide(threadRoot: nil, hasMention: nil, support: .supported, read: .notRead)
        #expect(decision == .show)
    }

    @Test func mentionShowsWithNoRead() {
        let decision = ThreadBannerRule.decide(threadRoot: "$root", hasMention: true, support: .supported, read: .notRead)
        #expect(decision == .show)
    }

    @Test func unknownStateNeedsARead() {
        let decision = ThreadBannerRule.decide(threadRoot: "$root", hasMention: nil, support: .supported, read: .notRead)
        #expect(decision == .readFollowState)
    }

    @Test func followedThreadShows() {
        let decision = ThreadBannerRule.decide(threadRoot: "$root", hasMention: false, support: .supported, read: .followed)
        #expect(decision == .show)
    }

    @Test func notFollowedThreadDrops() {
        let decision = ThreadBannerRule.decide(threadRoot: "$root", hasMention: false, support: .supported, read: .notFollowed)
        #expect(decision == .drop)
    }

    /// A failed read keeps the banner.
    @Test func failedReadShows() {
        let decision = ThreadBannerRule.decide(threadRoot: "$root", hasMention: false, support: .supported, read: .failed)
        #expect(decision == .show)
    }

    // MARK: Own root watch

    /// The roots that `observe` gives for each step, one sighting per step.
    private func arrivals(_ steps: [[OwnRootSighting]]) -> [[String]] {
        var watch = OwnRootReplyWatch()
        return steps.map { watch.observe($0) }
    }

    @Test func firstReplyToAWatchedMessageArrives() {
        let steps = arrivals([
            [OwnRootSighting(eventId: "$a", replyCount: 0)],
            [OwnRootSighting(eventId: "$a", replyCount: 1)],
            // The second reply is not a first reply.
            [OwnRootSighting(eventId: "$a", replyCount: 2)],
        ])
        #expect(steps == [[], ["$a"], []])
    }

    /// A message that loads with replies already is history.
    @Test func messageLoadedWithRepliesIsHistory() {
        let steps = arrivals([
            [OwnRootSighting(eventId: "$old", replyCount: 3)],
            [OwnRootSighting(eventId: "$old", replyCount: 4)],
        ])
        #expect(steps == [[], []])
    }

    /// A message that leaves the timeline stops being watched.
    @Test func messageOutOfTheTimelineIsNotWatched() {
        let steps = arrivals([
            [OwnRootSighting(eventId: "$a", replyCount: 0)],
            [],
            [OwnRootSighting(eventId: "$a", replyCount: 1)],
        ])
        #expect(steps == [[], [], []])
    }

    @Test func severalFirstRepliesKeepTheTimelineOrder() {
        var watch = OwnRootReplyWatch()
        _ = watch.observe([OwnRootSighting(eventId: "$a", replyCount: 0), OwnRootSighting(eventId: "$b", replyCount: 0)])
        let arrived = watch.observe([OwnRootSighting(eventId: "$a", replyCount: 1), OwnRootSighting(eventId: "$b", replyCount: 2)])
        #expect(arrived == ["$a", "$b"])
    }

    // MARK: Own root rule

    @Test(arguments: [ThreadSubscriptionSupport.unknown, .unsupported])
    func serverWithoutMSC4306Skips(support: ThreadSubscriptionSupport) {
        let decision = OwnRootFollowRule.decide(support: support, isHandled: false, read: .notRead)
        #expect(decision == .skip(.serverWithoutThreadSubscriptions))
    }

    @Test func firstReplyReadsThenFollows() {
        #expect(OwnRootFollowRule.decide(support: .supported, isHandled: false, read: .notRead) == .readFollowState)
        #expect(OwnRootFollowRule.decide(support: .supported, isHandled: false, read: .notFollowed) == .follow)
    }

    @Test func alreadyFollowedSkips() {
        #expect(OwnRootFollowRule.decide(support: .supported, isHandled: false, read: .followed) == .skip(.alreadyFollowed))
    }

    /// An Unfollow with the control marks the root as handled: the rule does
    /// not follow it again, with no read.
    @Test func alreadyUnfollowedSkips() {
        #expect(OwnRootFollowRule.decide(support: .supported, isHandled: true, read: .notRead) == .skip(.alreadyHandled))
        #expect(OwnRootFollowRule.decide(support: .supported, isHandled: true, read: .notFollowed) == .skip(.alreadyHandled))
    }

    @Test func failedReadSkips() {
        #expect(OwnRootFollowRule.decide(support: .supported, isHandled: false, read: .failed) == .skip(.readFailed))
    }

    // MARK: Support and the reset-once rule

    @Test func noEvidenceIsUnknown() {
        #expect(ThreadSubscriptionSupportRecord().support(at: start) == .unknown)
    }

    /// Records each step (evidence, seconds after `start`), and returns
    /// whether each step asks for a reset. `#expect` cannot call a mutating
    /// method.
    private func resets(_ record: inout ThreadSubscriptionSupportRecord, _ steps: [(ThreadSubscriptionEvidence, TimeInterval)]) -> [Bool] {
        steps.map { record.record($0.0, at: start.addingTimeInterval($0.1)) }
    }

    @Test(arguments: [ThreadSubscriptionEvidence.subscriptionRead, .changeAccepted])
    func firstSupportResetsOnce(evidence: ThreadSubscriptionEvidence) {
        var record = ThreadSubscriptionSupportRecord()
        // Later evidence does not reset again.
        let steps = resets(&record, [(evidence, 0), (.subscriptionRead, 60), (.changeAccepted, 120)])
        #expect(steps == [true, false, false])
        #expect(record.support(at: start.addingTimeInterval(120)) == .supported)
    }

    @Test func refusalIsUnsupportedAndNeverResets() {
        var record = ThreadSubscriptionSupportRecord()
        let steps = resets(&record, [(.endpointUnrecognized, 0), (.endpointUnrecognized, 60)])
        #expect(steps == [false, false])
        #expect(record.support(at: start.addingTimeInterval(60)) == .unsupported)
    }

    /// A server that loses MSC4306 and gets it back gets one more reset.
    @Test func supportAfterARefusalResetsAgain() {
        var record = ThreadSubscriptionSupportRecord()
        let first = resets(&record, [(.changeAccepted, 0), (.endpointUnrecognized, 60)])
        #expect(first == [true, false])
        #expect(record.support(at: start.addingTimeInterval(61)) == .unsupported)
        let second = resets(&record, [(.changeAccepted, 120)])
        #expect(second == [true])
        #expect(record.support(at: start.addingTimeInterval(121)) == .supported)
    }

    @Test func supportExpires() {
        var record = ThreadSubscriptionSupportRecord()
        _ = resets(&record, [(.subscriptionRead, 0)])
        let lifetime = ThreadSubscriptionSupportRecord.supportLifetime
        #expect(record.support(at: start.addingTimeInterval(lifetime)) == .supported)
        #expect(record.support(at: start.addingTimeInterval(lifetime + 1)) == .unknown)
        // An expiry does not reset again: the server did not change.
        let renewed = resets(&record, [(.subscriptionRead, lifetime + 2)])
        #expect(renewed == [false])
    }

    @Test func failedResetAsksAgain() {
        var record = ThreadSubscriptionSupportRecord()
        _ = resets(&record, [(.changeAccepted, 0)])
        record.versionsResetFailed()
        let next = resets(&record, [(.subscriptionRead, 1)])
        #expect(next == [true])
    }

    /// A relaunch reads the record back, and the next launch does not reset.
    @Test func recordSurvivesARelaunch() throws {
        var record = ThreadSubscriptionSupportRecord()
        _ = resets(&record, [(.changeAccepted, 0)])
        var relaunched = try JSONDecoder().decode(ThreadSubscriptionSupportRecord.self, from: JSONEncoder().encode(record))
        #expect(relaunched == record)
        let afterRelaunch = resets(&relaunched, [(.subscriptionRead, 1)])
        #expect(afterRelaunch == [false])
    }

    // MARK: Cache

    @Test func cacheHoldsAReadForItsLifetime() {
        var cache = ThreadFollowCache()
        #expect(cache.read(root: "$r", at: start) == .notRead)
        cache.store(isFollowed: false, root: "$r", at: start)
        #expect(cache.read(root: "$r", at: start.addingTimeInterval(ThreadFollowCache.lifetime - 1)) == .notFollowed)
        #expect(cache.read(root: "$r", at: start.addingTimeInterval(ThreadFollowCache.lifetime)) == .notRead)
        cache.store(isFollowed: true, root: "$r", at: start)
        #expect(cache.read(root: "$r", at: start) == .followed)
        cache.remove(root: "$r")
        #expect(cache.read(root: "$r", at: start) == .notRead)
    }

    // MARK: Handled roots

    @Test func handledRootsKeepTheNewest() {
        var roots = ThreadFollowHandledRoots()
        let inserts = [roots.insert("$a"), roots.insert("$a")]
        #expect(inserts == [true, false])
        for index in 0 ..< ThreadFollowHandledRoots.limit {
            roots.insert("$r\(index)")
        }
        #expect(roots.roots.count == ThreadFollowHandledRoots.limit)
        #expect(!roots.contains("$a"))
        #expect(roots.contains("$r\(ThreadFollowHandledRoots.limit - 1)"))
    }
}
