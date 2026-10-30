import Models
import OSLog
import SwiftUI
import Tokens
import UI
import UIKit
import Utils

/// The iOS timeline container (MATRIX-85): a flipped `UICollectionView` on a
/// stack layout fed by pre-measured heights, with `UIHostingConfiguration`
/// cells that render the shared row views.
///
/// The update model mirrors the Mac `TimelineViewController`:
/// - One `rows` array, newest first, holding the typing row (newest end), the
///   item rows, and the pagination row (oldest end). Heights, the cache, the
///   sender grouping, and the scroll anchor all address rows through it.
/// - Structural changes apply at once, as one non-animated step with the
///   measured-delta anchor compensation (S-33).
/// - Content-only changes queue for a display-link drain (MATRIX-57), and only
///   a height-relevant change re-measures (MATRIX-63 fingerprints).
@MainActor
final class TimelineCollectionController: NSObject {
    let feed: TimelineFeed
    var rowContext: TimelineRowContext

    let layout = TimelineStackLayout()
    let collectionView: UICollectionView

    var dataSource: UICollectionViewDiffableDataSource<Int, String>?
    /// The snapshot the collection view shows, mutated in place per change
    /// (S-34): one section, items in `rows` order.
    var snapshot = NSDiffableDataSourceSnapshot<Int, String>()

    var rows: [TimelineRow] = []
    /// Decoration rows at the newest end (the typing row). Item index `i`
    /// lives at row index `i + leadingDecorationCount`.
    var leadingDecorationCount = 0
    /// Decoration rows at the oldest end (pagination activity or failure).
    var trailingDecorationCount = 0

    var itemRowCount: Int {
        rows.count - leadingDecorationCount - trailingDecorationCount
    }

    /// Row heights keyed by (row id, width, cell tokens), invalidated by
    /// content revision (S-32).
    var heightCache = TimelineRowHeightCache<TimelineCellTokens>()
    /// Per-row content revision, bumped by a height-relevant content change.
    var rowRevisions: [String: Int] = [:]
    /// Per-row sender-header answer, keyed by identity so a renumbering
    /// structural change cannot misapply it. Absent means no header.
    var senderHeaders: Set<String> = []

    /// Content-only updates owed to the collection view (MATRIX-57).
    var pendingRowUpdates = TimelineRowUpdateQueue<TimelineRow>()
    var rowUpdateDisplayLink: CADisplayLink?
    var unpacedRowUpdateDrainScheduled = false

    /// True while a compensation writes the content offset.
    var isAdjustingScrollAnchor = false
    var scrollReportScheduled = false
    var timelineFetchTask: Task<Void, Never>?
    var handledScrollToBottomRequests: Int
    var handledFocusRequestId: String?
    var pendingFocus = false
    var focusScrollScheduled = false

    /// Offscreen host for measurement. One view type for cells and
    /// measurement, so a measured height is the drawn height.
    private let measurementHost = UIHostingController(rootView: AnyView(EmptyView()))

    init(feed: TimelineFeed, rowContext: TimelineRowContext) {
        self.feed = feed
        self.rowContext = rowContext
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        // A request made before this container existed is not a request to
        // this container.
        handledScrollToBottomRequests = feed.scrollToBottomRequests
        super.init()

        // Start from the current display order and take ownership of the
        // change queue, so the first update applies only what happens next.
        rows = feed.displayRows
        _ = feed.drainRowChanges()
        refreshDecorationRows(applying: false)
        regroup(0 ..< rows.count)

        configureCollectionView()
        rebuildSnapshot()
        observeFeed()
        scheduleScrollReport()
    }

    private func configureCollectionView() {
        layout.heightSource = self

        // The flip puts the document origin, row 0, the newest message, at
        // the bottom of the screen. See `TimelineStackLayout`.
        collectionView.transform = TimelineStackLayout.cellTransform
        collectionView.backgroundColor = .systemBackground
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .interactive
        // The status-bar tap scrolls to the document origin, which the flip
        // makes the newest end. The scroll-to-bottom chip owns that move.
        collectionView.scrollsToTop = false
        collectionView.delegate = self

        let provider: UICollectionViewDiffableDataSource<Int, String>.CellProvider = { [weak self] collectionView, indexPath, _ in
            self?.cell(in: collectionView, at: indexPath) ?? UICollectionViewCell()
        }
        dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView, cellProvider: provider)
    }

    // MARK: - Cells

    /// Reuse identifiers registered so far. `TimelineRow.reuseId` keeps a
    /// recycled cell's SwiftUI tree structurally close to the row it gets.
    private var registeredReuseIds: Set<String> = []

    private func cell(in collectionView: UICollectionView, at indexPath: IndexPath) -> UICollectionViewCell {
        guard rows.indices.contains(indexPath.item) else { return UICollectionViewCell() }
        let row = rows[indexPath.item]
        if !registeredReuseIds.contains(row.reuseId) {
            collectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: row.reuseId)
            registeredReuseIds.insert(row.reuseId)
        }
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: row.reuseId, for: indexPath)
        cell.contentConfiguration = contentConfiguration(for: row)
        return cell
    }

    func contentConfiguration(for row: TimelineRow) -> UIContentConfiguration {
        UIHostingConfiguration { rowView(for: row) }
            .margins(.all, 0)
            .minSize(width: nil, height: 0)
    }

    private func rowView(for row: TimelineRow) -> TimelineRowContent {
        TimelineRowContent(
            row: row,
            showsSenderHeader: senderHeaders.contains(row.uniqueId),
            context: rowContext
        )
    }

    /// Redraws a visible row in place. An offscreen row needs nothing: its
    /// cell is configured from `rows` when it appears.
    func reconfigureVisibleCell(atRow row: Int) {
        guard let cell = collectionView.cellForItem(at: IndexPath(item: row, section: 0)) else { return }
        cell.contentConfiguration = contentConfiguration(for: rows[row])
    }

    // MARK: - Sender grouping

    /// Re-answers the sender-header question for `range`, and returns the row
    /// indices whose answer changed. A changed answer is a height change: the
    /// cache keys on it through `TimelineCellTokens`.
    @discardableResult
    func regroup(_ range: Range<Int>) -> [Int] {
        var changed: [Int] = []
        for index in range where rows.indices.contains(index) {
            let row = rows[index]
            let older = index + 1 < rows.count ? rows[index + 1] : nil
            let shows = TimelineSenderGrouping.showsSenderHeader(row, olderNeighbor: older)
            if shows != senderHeaders.contains(row.uniqueId) {
                if shows {
                    senderHeaders.insert(row.uniqueId)
                } else {
                    senderHeaders.remove(row.uniqueId)
                }
                changed.append(index)
            }
        }
        return changed
    }

    // MARK: - Feed observation

    /// Watches the feed and applies its changes after the write that caused
    /// them, outside any SwiftUI update pass (the S-54 re-entrancy).
    ///
    /// Tracking is one-shot and re-armed from the hop, so a burst of writes in
    /// one runloop turn costs one update.
    private func observeFeed() {
        withObservationTracking {
            feed.touchObservedState()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeFeed()
                self.update()
            }
        }
    }

    /// Applies everything the feed changed since the last update.
    func update() {
        applyPendingTimelineChanges()
        refreshDecorationRows(applying: true)
        handleScrollToBottomRequests()
        handleFocusRequest()
    }

    /// The row context changed (typography, own user, receipts flag): every
    /// height is suspect and every visible cell redraws.
    func rowContextDidChange(from old: TimelineRowContext) {
        guard old.typography != rowContext.typography
            || old.showsReadReceipts != rowContext.showsReadReceipts
            || old.ownUserId != rowContext.ownUserId
        else { return }
        heightCache.invalidateAll()
        for indexPath in collectionView.indexPathsForVisibleItems {
            reconfigureVisibleCell(atRow: indexPath.item)
        }
        layout.invalidateLayout()
    }

    // MARK: - Measurement

    /// Measures one row offscreen at `width`: the source behind the cache,
    /// called only on a miss.
    private func measureRowHeight(_ row: TimelineRow, width: CGFloat) -> CGFloat {
        measurementHost.rootView = AnyView(rowView(for: row))
        return measurementHost.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    func cellTokens(for row: TimelineRow) -> TimelineCellTokens {
        TimelineCellTokens(typography: rowContext.typography, showsSenderHeader: senderHeaders.contains(row.uniqueId))
    }
}

/// The per-row half of a height cache key: the active typography, and whether
/// the row draws the sender header. Either changing re-measures the row.
struct TimelineCellTokens: Hashable {
    let typography: TimelineTypography
    let showsSenderHeader: Bool
}

extension TimelineCollectionController: TimelineStackLayoutHeightSource {
    func rowHeights(forWidth width: CGFloat) -> [CGFloat] {
        guard width > 0 else { return Array(repeating: 1, count: rows.count) }
        var heights: [CGFloat] = []
        heights.reserveCapacity(rows.count)
        for row in rows {
            let height = heightCache.height(
                for: row,
                width: width,
                tokens: cellTokens(for: row),
                revision: rowRevisions[row.uniqueId] ?? 0
            ) { row, width in
                self.measureRowHeight(row, width: width)
            }
            heights.append(height)
        }
        return heights
    }
}
