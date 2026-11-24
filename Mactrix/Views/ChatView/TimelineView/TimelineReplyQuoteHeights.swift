// The timeline spike compiles the controller without Core (see spike/GATE.md),
// and this file is not linked into the spike, so the controller reaches it only
// under `canImport(Core)`.
#if canImport(Core)
    import AppKit
    import Core
    import MatrixRustSDK
    import Models

    // MATRIX-230: a reply row is measured while its quote is a placeholder.
    // When the SDK resolves the quote itself, a row update carries it and the
    // fingerprint sees the change. When `LiveTimeline` loads it, no row update
    // follows: the row draws the new quote by itself and kept the
    // placeholder's height, so the space the placeholder needed stayed in the
    // row. The load now reaches the height cache through the same fingerprint
    // test as a row update.
    extension TimelineViewController {
        /// Listens for the replied-to events that a shown room timeline loads
        /// itself.
        func listenForReplyDetails() {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleReplyDetailsDidLoad(_:)),
                name: LiveTimeline.replyDetailsDidLoad,
                object: nil
            )
        }

        /// A replied-to event loaded. It runs on the main actor, after the
        /// timeline stored the details, and outside a SwiftUI update or an
        /// AppKit layout pass, so the re-measure runs now.
        @objc func handleReplyDetailsDidLoad(_ notification: Notification) {
            guard let timeline = notification.object as? LiveTimeline,
                  source.actionTimelines.contains(where: { $0 === timeline }),
                  let eventId = notification.userInfo?[LiveTimeline.loadedReplyEventIdKey] as? String,
                  let details = timeline.loadedReplyDetails[eventId]
            else { return }
            remeasureRows(quoting: eventId, in: timeline, as: details.event().replyQuote)
        }

        /// Puts the loaded quote in the fingerprint of each row of `timeline`
        /// that quotes `eventId`, and measures again the rows whose height
        /// it can change.
        ///
        /// The view of a visible row redraws with the new quote by itself
        /// (it reads `loadedReplyDetails`), so only the heights are noted.
        /// The S-33 anchor holds the visible content still, as for a
        /// structural batch. The table is unflipped, so a row above the
        /// viewport moves no visible row; a row below it does, and the
        /// restore moves the viewport by the same distance.
        func remeasureRows(quoting eventId: String, in timeline: LiveTimeline, as quote: ReplyQuoteGeometry) {
            let source = source
            let changed = LoadedReplyQuote.apply(quote, quoting: eventId, to: &timelineRows) { row in
                source.timeline(for: row) === timeline
            }
            guard !changed.isEmpty else { return }
            // The revision bump drops each cached height (S-32).
            for index in changed {
                rowRevisions[timelineRows[index].uniqueId, default: 0] += 1
            }

            let anchor = currentScrollAnchor()
            // Zero duration for the MATRIX-49 reason: a re-noted row must not
            // be clipped to its old frame while an implicit animation runs.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                context.allowsImplicitAnimation = false

                tableView.noteHeightOfRows(withIndexesChanged: changed)
                if let anchor {
                    tableView.tile()
                    restoreScrollAnchor(anchor)
                } else if case .row = liveResizeHold {
                    tableView.tile()
                    holdLiveResizeAnchor()
                }
            }
        }
    }
#endif
