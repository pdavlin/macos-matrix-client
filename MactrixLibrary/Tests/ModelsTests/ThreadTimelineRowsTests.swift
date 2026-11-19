import Foundation
@testable import Models
import Testing

/// MATRIX-183: the thread panel's "N replies" divider row: its identity, its
/// fixed height, its place after the root, and the changes that keep the
/// container's rows in step with the thread timeline.
struct ThreadTimelineRowsTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)

    private static func message(_ id: String) -> TimelineRow {
        .message(
            uniqueId: id,
            event: GroupingTestEvent(sender: "@ben:example.org", date: start),
            kind: .text,
            heightFingerprint: .stub()
        )
    }

    /// A thread newest first: three replies, the root, and a day divider.
    private static var base: [TimelineRow] {
        [
            message("r3"), message("r2"), message("r1"), message("root"),
            .virtual(uniqueId: "day", item: .dateDivider(date: start)),
        ]
    }

    private static func anchor(_ count: Int) -> ThreadDividerAnchor {
        ThreadDividerAnchor(rootRowId: "root", replyCount: count)
    }

    private func ids(_ rows: [TimelineRow]) -> [String] {
        rows.map(\.uniqueId)
    }

    /// Replays `updates` on `rows` as the container does.
    private func applying(_ updates: [TimelineRowDisplayUpdate], to rows: [TimelineRow]) -> [TimelineRow] {
        var result = rows
        for update in updates {
            switch update.change {
            case let .insert(index, _):
                result.insert(contentsOf: update.rows, at: index)
            case let .remove(index, count):
                result.removeSubrange(index ..< index + count)
            case let .update(index):
                if let row = update.rows.first {
                    result[index] = row
                }
            case .reset:
                Issue.record("unexpected reset")
            }
        }
        return result
    }

    // MARK: Identity and height

    @Test func dividerIdentityIsStableForOneCount() {
        #expect(ThreadRepliesDivider.rowId(count: 4) == ThreadRepliesDivider.rowId(count: 4))
        #expect(ThreadRepliesDivider.row(count: 4).uniqueId == ThreadRepliesDivider.rowId(count: 4))
        #expect(ThreadRepliesDivider.row(count: 4).reuseId == ThreadRepliesDivider.row(count: 9).reuseId)
        #expect(ThreadRepliesDivider.row(count: 4).reuseId == "virtual.threadReplies")
    }

    /// A new count is a new row, so the container never reuses a view or a
    /// height made for the old text.
    @Test func aNewCountIsANewIdentity() {
        #expect(ThreadRepliesDivider.rowId(count: 4) != ThreadRepliesDivider.rowId(count: 5))
    }

    @Test func dividerHasAFixedHeightAndIsNotMeasured() {
        var measured = 0
        let height = TimelineRowMeasurement.height(of: ThreadRepliesDivider.row(count: 4), width: 300) { _, _ in
            measured += 1
            return 99
        }
        #expect(height == ThreadRepliesDivider.rowHeight)
        #expect(measured == 0)
        #expect(ThreadRepliesDivider.row(count: 4).heightFingerprint == nil)
    }

    // MARK: Place

    @Test func dividerGoesRightAfterTheRoot() {
        let rows = ThreadRepliesDivider.inserting(into: Self.base, anchor: Self.anchor(3))
        #expect(ids(rows) == ["r3", "r2", "r1", ThreadRepliesDivider.rowId(count: 3), "root", "day"])
    }

    @Test func noDividerWithoutAnchorRootOrReply() {
        #expect(ids(ThreadRepliesDivider.inserting(into: Self.base, anchor: nil)) == ids(Self.base))
        #expect(ids(ThreadRepliesDivider.inserting(into: Self.base, anchor: Self.anchor(0))) == ids(Self.base))
        let missingRoot = ThreadDividerAnchor(rootRowId: "elsewhere", replyCount: 3)
        #expect(ids(ThreadRepliesDivider.inserting(into: Self.base, anchor: missingRoot)) == ids(Self.base))
    }

    @Test func factsGiveAnAnchorOnlyWithRootAndCount() {
        #expect(ThreadTimelineFacts(replyCount: 3, rootRowId: "root").dividerAnchor == Self.anchor(3))
        #expect(ThreadTimelineFacts(replyCount: 3, rootRowId: nil).dividerAnchor == nil)
        #expect(ThreadTimelineFacts(replyCount: nil, rootRowId: "root").dividerAnchor == nil)
    }

    // MARK: Changes

    @Test func aNewReplyMovesTheCountAndKeepsEveryOtherRow() {
        var model = ThreadTimelineRows()
        let before = model.start(base: Self.base, anchor: Self.anchor(3))

        let updates = model.apply(
            [TimelineRowDisplayUpdate(change: .insert(index: 0, count: 1), rows: [Self.message("r4")])],
            anchor: Self.anchor(4)
        )

        let expected = ["r4", "r3", "r2", "r1", ThreadRepliesDivider.rowId(count: 4), "root", "day"]
        #expect(ids(model.rows) == expected)
        #expect(ids(applying(updates, to: before)) == expected)
        #expect(!updates.contains { $0.change == .reset })
    }

    /// An edit of a reply is one content update, and the divider does not
    /// move or change its identity.
    @Test func anEditKeepsTheDividerInPlace() {
        var model = ThreadTimelineRows()
        let before = model.start(base: Self.base, anchor: Self.anchor(3))

        let updates = model.apply(
            [TimelineRowDisplayUpdate(change: .update(index: 1), rows: [Self.message("r2")])],
            anchor: Self.anchor(3)
        )

        #expect(updates.map(\.change) == [.update(index: 1)])
        #expect(ids(model.rows) == ids(before))
    }

    /// The root is older than the divider: its index in the container's rows
    /// is one more than in the thread's own rows.
    @Test func anUpdateOfTheRootLandsAfterTheDivider() {
        var model = ThreadTimelineRows()
        _ = model.start(base: Self.base, anchor: Self.anchor(3))

        let updates = model.apply(
            [TimelineRowDisplayUpdate(change: .update(index: 3), rows: [Self.message("root")])],
            anchor: Self.anchor(3)
        )

        #expect(updates.map(\.change) == [.update(index: 4)])
    }

    @Test func noChangeGivesNoUpdate() {
        var model = ThreadTimelineRows()
        _ = model.start(base: Self.base, anchor: Self.anchor(3))
        #expect(model.apply([], anchor: Self.anchor(3)).isEmpty)
    }

    /// The root arrives after the replies (an older page): the divider comes
    /// with it.
    @Test func theDividerComesWithTheRoot() {
        var model = ThreadTimelineRows()
        let before = model.start(base: Array(Self.base.prefix(3)), anchor: ThreadTimelineFacts(replyCount: 3).dividerAnchor)

        let updates = model.apply(
            [TimelineRowDisplayUpdate(change: .insert(index: 3, count: 2), rows: Array(Self.base.suffix(2)))],
            anchor: Self.anchor(3)
        )

        let expected = ["r3", "r2", "r1", ThreadRepliesDivider.rowId(count: 3), "root", "day"]
        #expect(ids(model.rows) == expected)
        #expect(ids(applying(updates, to: before)) == expected)
    }

    @Test func aResetOfTheThreadIsAReset() {
        var model = ThreadTimelineRows()
        _ = model.start(base: Self.base, anchor: Self.anchor(3))
        let updates = model.apply([TimelineRowDisplayUpdate(change: .reset)], anchor: Self.anchor(3))
        #expect(updates.map(\.change) == [.reset])
    }

    @Test func anIndexThatDoesNotMatchIsAReset() {
        var model = ThreadTimelineRows()
        _ = model.start(base: Self.base, anchor: Self.anchor(3))
        let updates = model.apply([TimelineRowDisplayUpdate(change: .remove(index: 9, count: 1))], anchor: Self.anchor(3))
        #expect(updates.map(\.change) == [.reset])
    }
}
