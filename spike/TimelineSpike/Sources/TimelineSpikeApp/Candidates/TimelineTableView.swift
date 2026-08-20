import AppKit
import QuartzCore
import TimelineSpikeCore

/// The AppKit candidate's view: one `NSScrollView` over one `NSTableView`, with the height
/// bookkeeping and the scroll anchoring done by hand.
///
/// ## Why `NSTableView` and not `NSCollectionView`
///
/// `NSCollectionView` on macOS has no self-sizing items — `estimatedItemSize` is a UIKit
/// feature — so variable heights mean a custom layout that computes attributes for every
/// item, and one changed row means `invalidateLayout()` and a fresh attribute pass over the
/// loaded window. `NSTableView` has `noteHeightOfRows(withIndexesChanged:)`, which
/// invalidates exactly the rows named and re-tiles once. That method is the reason to pick
/// the table: it is the in-place height update the mutation storm needs, and the collection
/// view has no equivalent. `NSCollectionView` would win if the timeline were a grid or needed
/// animated moves. It is neither.
///
/// ## Heights
///
/// `usesAutomaticRowHeights` is **off**. It resolves a row's height from Auto Layout at
/// display time, so the scroll view learns the document's real height only as rows come into
/// view and corrects it by moving content that is already on screen — which is the jump S4
/// measures. Instead `SpikeRowHeightModel` measures every loaded row up front,
/// `RowHeightCache` answers `heightOfRow:` in O(1), and the document height is exact from the
/// first frame. The cost is one Core Text pass over the corpus at load, printed at startup so
/// it lands in the story rather than hiding.
///
/// ## Anchoring
///
/// A prepend and an off-screen height change both push the content below them down, and both
/// are absorbed the same way. The row at the top edge of the viewport is measured before the
/// table update and again after it; the viewport moves by the difference. Measuring rather
/// than predicting means the compensation is right even if `NSTableView` moves rows on its
/// own — the predicted delta is still computed and compared, and a disagreement is printed,
/// because that disagreement is a finding.
///
/// Table update and compensating scroll happen inside one `CATransaction` with implicit
/// actions disabled, so the intermediate geometry is never presented.
@MainActor
final class TimelineTableView: NSView {
    private let harness: SpikeHarness
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let model: SpikeRowHeightModel
    private let auditor: RowHeightAuditor?

    private var cache = RowHeightCache()

    /// Identity of the store the table currently reflects. The console can replace the store
    /// wholesale with "Regenerate", which is a full reload rather than a diff.
    private var renderedStore: ObjectIdentifier?
    /// Generator index of table row 0. Row indices shift on every prepend; identifiers do
    /// not, so every row/identifier conversion goes through this.
    private var renderedOldestIndex = 0
    private var renderedRowCount = 0
    /// The store's mutation tally at the last sync. Every applied mutation increments it, so
    /// comparing it is an exact test for "nothing changed", not a heuristic.
    private var renderedMutationCount = 0
    private var rowWidth: CGFloat = 0

    private var isApplyingStoreChange = false
    private var hasLoaded = false
    private var pendingScrollReport = false
    private var lastReportedVisibleRange: NSRange?
    private var anchorDisagreementsReported = 0

    /// The row at the top edge of the viewport, captured before a table update.
    private struct AnchorSnapshot {
        var eventID: EventID
        /// Row index at capture time. Prepends shift it, `eventID` does not.
        var row: Int
        /// Top of the row in the document's coordinates.
        var documentTop: CGFloat
        /// Points from the top of the viewport to the top of the row.
        var offsetInViewport: CGFloat
    }

    init(harness: SpikeHarness) {
        self.harness = harness
        self.model = SpikeRowHeightModel(measurer: CoreTextSpikeMeasurer())
        self.auditor = RowHeightAuditor.isEnabled ? RowHeightAuditor() : nil
        super.init(frame: .zero)
        configureTable()
        configureScrollView()
        if auditor != nil {
            print("[AppKitTable] height audit enabled; this run's numbers are not comparable.")
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        preconditionFailure("TimelineTableView is created in code, never from a nib")
    }

    // MARK: - Setup

    private func configureTable() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("spike.timeline"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        // `.plain`, not `.automatic`: the inset styles add horizontal margins of their own,
        // which would make the row narrower than `SpikeRowMetrics` assumes and change where
        // the text wraps.
        tableView.style = .plain
        tableView.rowSizeStyle = .custom
        tableView.usesAutomaticRowHeights = false
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.gridStyleMask = []
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = .textBackgroundColor
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
    }

    private func configureScrollView() {
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        // Deterministic geometry: an automatic inset would silently change the viewport
        // height and with it every offset reported to the probe.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        // The row width is the clip view's width, which is narrower than this view's width
        // when the user has legacy (non-overlay) scrollers switched on.
        let width = scrollView.contentSize.width
        guard width > 0, width != rowWidth else { return }
        applyRowWidth(width)
    }

    /// A width change invalidates every measured height, so it is a full rebuild. It is also
    /// why SCENARIOS.md says not to resize the window during a run.
    private func applyRowWidth(_ width: CGFloat) {
        let anchor = hasLoaded ? currentAnchor() : nil
        rowWidth = width
        hasLoaded = true
        reloadEverything(anchor: anchor)
    }

    // MARK: - Store synchronisation

    /// Brings the table in line with the store. Called from `updateNSView` on every change
    /// SwiftUI observes, which is every mutation tick and every prepend.
    func sync() {
        guard rowWidth > 0 else { return }
        let store = harness.store
        guard ObjectIdentifier(store) == renderedStore else {
            hasLoaded = true
            reloadEverything(anchor: nil)
            return
        }

        // SwiftUI also re-evaluates this view when the HUD ticks, which has nothing to do with
        // the timeline. `appliedMutationCount` rises with every applied mutation and
        // `oldestIndex` falls with every prepend, so together they are an exact test for "the
        // store did not change" — not a throttle and not a coalescer, because no store change
        // can pass this guard unseen.
        let insertedCount = renderedOldestIndex - store.oldestIndex
        guard insertedCount != 0 || store.appliedMutationCount != renderedMutationCount else {
            reportGeometry()
            return
        }

        // Reading `items` once into a local costs one retain. Reading it per row inside the
        // diff would pay the observation registrar's access check ten thousand times, and
        // holding it in a property would force the store to copy the whole array on its next
        // write. The local is released when this call returns.
        let items = store.items
        guard insertedCount >= 0, items.count == renderedRowCount + insertedCount else {
            // The store changed in a way its invariants say it cannot. Reload rather than
            // corrupt the row mapping.
            reloadEverything(anchor: currentAnchor())
            return
        }

        isApplyingStoreChange = true
        withoutAnimation {
            let anchor = currentAnchor()
            var predictedDelta: CGFloat = 0
            if insertedCount > 0 {
                predictedDelta += applyPrepend(
                    count: insertedCount,
                    items: items,
                    oldestIndex: store.oldestIndex
                )
            }
            predictedDelta += applyHeightChanges(
                items: items,
                anchorRow: (anchor?.row ?? 0) + insertedCount
            )
            restoreAnchor(anchor, predictedDelta: predictedDelta)
        }
        renderedMutationCount = store.appliedMutationCount
        isApplyingStoreChange = false

        reportGeometry()
        flushPendingScrollReport()
    }

    /// Absorbs a back-pagination batch.
    ///
    /// The new rows are measured before anything moves, so the inserted height is known
    /// exactly. `tile()` runs straight after the insertion because the compensating scroll is
    /// clamped against the document height: leave the table believing in the old, shorter
    /// document and the clamp caps the very move that hides the jump.
    ///
    /// - Returns: the height the document gained, which is what the viewport should move by.
    @discardableResult
    private func applyPrepend(count: Int, items: [TimelineItem], oldestIndex: Int) -> CGFloat {
        let insertedHeight = cache.insertPrefix(items[0 ..< count], model: model)
        renderedOldestIndex = oldestIndex
        renderedRowCount += count

        tableView.beginUpdates()
        tableView.insertRows(at: IndexSet(integersIn: 0 ..< count), withAnimation: [])
        tableView.endUpdates()
        tableView.tile()
        return insertedHeight
    }

    /// Applies a mutation tick: new content into the on-screen cells, new heights into the
    /// table.
    ///
    /// - Returns: the predicted anchor movement, for the cross-check in `restoreAnchor`.
    @discardableResult
    private func applyHeightChanges(items: [TimelineItem], anchorRow: Int) -> CGFloat {
        let (changedRows, changes) = cache.refresh(items: items, model: model)
        guard !changedRows.isEmpty else { return 0 }

        // A height change alone would leave the old text sitting in a new-sized box, so the
        // visible cells are re-hosted. Off-screen rows are not touched: they get their content
        // when the table next asks for them.
        for row in changedRows {
            guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false)
                as? SpikeRowHostingView else { continue }
            cell.configure(item: items[row], rowWidth: rowWidth)
        }

        guard !changes.isEmpty else { return 0 }
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(changes.map(\.row)))
        tableView.tile()
        return ScrollAnchorMath.compensation(for: changes, anchorRow: anchorRow)
    }

    /// Puts the anchor row back where it was on screen.
    ///
    /// The measured delta is authoritative. `predictedDelta` is what the height bookkeeping
    /// says should have happened; when the two disagree, `NSTableView` moved rows on its own
    /// and the compensation would have double-counted. That is worth knowing, so it is
    /// printed — a few times, not on every tick.
    private func restoreAnchor(_ anchor: AnchorSnapshot?, predictedDelta: CGFloat) {
        guard let anchor, let row = row(for: anchor.eventID) else { return }
        let measuredDelta = tableView.rect(ofRow: row).minY - anchor.documentTop

        if abs(measuredDelta - predictedDelta) > 0.5, anchorDisagreementsReported < 5 {
            anchorDisagreementsReported += 1
            print(
                "[AppKitTable] anchor delta measured "
                    + String(format: "%.2f", measuredDelta)
                    + " but predicted " + String(format: "%.2f", predictedDelta)
                    + "; the table moved rows on its own."
            )
        }

        guard measuredDelta != 0 else { return }
        let clipView = scrollView.contentView
        setOriginY(
            ScrollAnchorMath.originRestoringAnchor(
                currentOriginY: clipView.bounds.origin.y,
                anchorTopBefore: anchor.documentTop,
                anchorTopAfter: anchor.documentTop + measuredDelta,
                maximumOriginY: maximumOriginY()
            ),
            x: clipView.bounds.origin.x
        )
    }

    /// Full rebuild. Used for the first layout, a width change and a regenerated store.
    private func reloadEverything(anchor: AnchorSnapshot?) {
        let store = harness.store
        let items = store.items
        renderedStore = ObjectIdentifier(store)
        renderedOldestIndex = store.oldestIndex
        renderedRowCount = items.count
        renderedMutationCount = store.appliedMutationCount
        lastReportedVisibleRange = nil

        let started = CACurrentMediaTime()
        cache.rebuild(items: items, rowWidth: rowWidth, model: model)
        let elapsed = (CACurrentMediaTime() - started) * 1000
        print(
            "[AppKitTable] measured \(items.count) rows at \(Int(rowWidth))pt in "
                + String(format: "%.1f", elapsed) + " ms"
        )

        withoutAnimation {
            tableView.reloadData()
            tableView.tile()
            let clipView = scrollView.contentView
            if let anchor, let row = row(for: anchor.eventID) {
                setOriginY(
                    ScrollAnchorMath.clamped(
                        tableView.rect(ofRow: row).minY - anchor.offsetInViewport,
                        maximumOriginY: maximumOriginY()
                    ),
                    x: clipView.bounds.origin.x
                )
            } else {
                // The timeline opens on the newest event, the way a chat client does.
                setOriginY(maximumOriginY(), x: clipView.bounds.origin.x)
            }
        }
        reportGeometry()
    }

    // MARK: - Geometry reporting

    /// Feeds the probe. Visible set first, because reporting it can retarget the tracked
    /// event, and the offset must belong to whichever event is tracked *after* that.
    private func reportGeometry() {
        let probe = harness.probe
        let visible = tableView.rows(in: tableView.visibleRect)

        if visible.length <= 0 {
            if lastReportedVisibleRange != nil {
                lastReportedVisibleRange = nil
                probe.reportVisible([], range: nil)
            }
        } else if visible != lastReportedVisibleRange {
            lastReportedVisibleRange = visible
            let upper = visible.location + visible.length
            var ids: [EventID] = []
            ids.reserveCapacity(visible.length)
            for row in visible.location ..< upper {
                ids.append(EventID(renderedOldestIndex + row))
            }
            // The mutation driver indexes into `store.items`, and the store can be one prepend
            // ahead of the table between an automatic prepend and the next update.
            let shift = renderedOldestIndex - harness.store.oldestIndex
            probe.reportVisible(ids, range: (visible.location + shift) ..< (upper + shift))
        }

        // The offset goes out on every geometry change, not only when the visible set moves: a
        // height change above the tracked row moves it without changing which rows are on
        // screen, and that is the drift the probe exists to catch.
        //
        // `AnchorProbe`'s documentation suggests `convert(rowRect, to: clipView).minY` for an
        // AppKit candidate. That is not the number the probe wants. A document view's frame
        // lives in the clip view's *bounds* space, and scrolling moves the clip view's bounds
        // origin rather than the document's frame, so the converted value is the row's
        // position in the document and it carries the scroll position with it — every scroll
        // would then read as drift. Subtracting the bounds origin is what leaves the on-screen
        // position behind.
        guard let tracked = probe.trackedID, let row = row(for: tracked) else { return }
        let rowTop = tableView.rect(ofRow: row).minY
        probe.reportOffset(Double(rowTop - scrollView.contentView.bounds.origin.y), for: tracked)
    }

    @objc
    private func clipViewBoundsDidChange(_: Notification) {
        reportGeometry()
        guard !isApplyingStoreChange else {
            // The anchor compensation moves the origin itself. Telling the pagination driver
            // about that move while the store update is still in flight would re-enter the
            // driver mid-change; the report goes out intact as soon as the update finishes.
            pendingScrollReport = true
            return
        }
        harness.viewportDidScroll(distanceFromTop: Double(scrollView.contentView.bounds.origin.y))
    }

    private func flushPendingScrollReport() {
        guard pendingScrollReport else { return }
        pendingScrollReport = false
        harness.viewportDidScroll(distanceFromTop: Double(scrollView.contentView.bounds.origin.y))
    }

    // MARK: - Helpers

    private func item(atRow row: Int) -> TimelineItem? {
        let store = harness.store
        guard let index = store.itemIndex(for: EventID(renderedOldestIndex + row)) else {
            return nil
        }
        return store.items[index]
    }

    private func row(for id: EventID) -> Int? {
        let row = id.rawValue - renderedOldestIndex
        return (0 ..< renderedRowCount).contains(row) ? row : nil
    }

    /// The row at the top edge of the viewport, or `nil` when the table is empty.
    private func currentAnchor() -> AnchorSnapshot? {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return nil }
        let rowRect = tableView.rect(ofRow: visible.location)
        return AnchorSnapshot(
            eventID: EventID(renderedOldestIndex + visible.location),
            row: visible.location,
            documentTop: rowRect.minY,
            offsetInViewport: rowRect.minY - scrollView.contentView.bounds.origin.y
        )
    }

    /// Moves the viewport the way a trackpad would.
    ///
    /// A test seam. There is no trackpad in a test process, and the anchoring behaviour that
    /// matters is the behaviour away from the top and bottom edges, where the clamp is not
    /// doing the work.
    func scrollViewport(toDistanceFromTop distance: CGFloat) {
        setOriginY(
            ScrollAnchorMath.clamped(distance, maximumOriginY: maximumOriginY()),
            x: scrollView.contentView.bounds.origin.x
        )
    }

    private func maximumOriginY() -> CGFloat {
        ScrollAnchorMath.maximumOriginY(
            documentHeight: tableView.frame.height,
            viewportHeight: scrollView.contentView.bounds.height
        )
    }

    private func setOriginY(_ originY: CGFloat, x originX: CGFloat) {
        let clipView = scrollView.contentView
        guard originY != clipView.bounds.origin.y else { return }
        clipView.setBoundsOrigin(NSPoint(x: originX, y: originY))
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Runs a table update with every implicit animation switched off.
    ///
    /// `NSTableView` animates row insertions and height changes by default. An animated
    /// prepend is a visible jump under another name, and an animated height change would
    /// smear the drift measurement across frames.
    private func withoutAnimation(_ body: () -> Void) {
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
        NSAnimationContext.endGrouping()
    }
}

// MARK: - Table data source and delegate

extension TimelineTableView: NSTableViewDataSource {
    func numberOfRows(in _: NSTableView) -> Int {
        renderedRowCount
    }
}

extension TimelineTableView: NSTableViewDelegate {
    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        max(1, cache.height(row: row))
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor _: NSTableColumn?,
        row: Int
    ) -> NSView? {
        let recycled = tableView.makeView(
            withIdentifier: SpikeRowHostingView.reuseIdentifier,
            owner: self
        ) as? SpikeRowHostingView
        let view = recycled ?? SpikeRowHostingView()
        guard let item = item(atRow: row) else { return view }
        view.configure(item: item, rowWidth: rowWidth)
        auditor?.audit(item: item, rowWidth: rowWidth, modelledHeight: cache.height(row: row))
        return view
    }

    func tableView(_: NSTableView, shouldSelectRow _: Int) -> Bool {
        false
    }
}
