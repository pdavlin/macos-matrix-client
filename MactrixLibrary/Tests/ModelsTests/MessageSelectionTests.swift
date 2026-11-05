import Models
import Testing

/// MATRIX-113 (M2-B6, D-2): whole-message selection by gutter clicks.
struct MessageSelectionTests {
    /// Display order, newest first, as the timeline container passes it.
    private let order = ["e", "d", "c", "b", "a"]

    @Test func gestureFollowsTheModifierKeys() {
        #expect(MessageSelectionGesture(isShiftDown: false, isCommandDown: false) == .select)
        #expect(MessageSelectionGesture(isShiftDown: true, isCommandDown: false) == .extend)
        #expect(MessageSelectionGesture(isShiftDown: false, isCommandDown: true) == .toggle)
        #expect(MessageSelectionGesture(isShiftDown: true, isCommandDown: true) == .toggle)
    }

    @Test func startsEmpty() {
        let selection = MessageSelection()
        #expect(selection.isEmpty)
        #expect(selection.anchorId == nil)
    }

    @Test func clickSelectsOnlyTheClickedMessage() {
        var selection = MessageSelection()
        selection.apply(.select, to: "b", order: order)
        selection.apply(.select, to: "d", order: order)
        #expect(selection.selectedIds == ["d"])
        #expect(selection.anchorId == "d")
    }

    @Test func shiftClickSelectsTheRangeFromTheAnchor() {
        var selection = MessageSelection()
        selection.apply(.select, to: "b", order: order)
        selection.apply(.extend, to: "d", order: order)
        #expect(selection.selectedIds == ["b", "c", "d"])
        // The anchor stays, so a second Shift-click re-ranges from it.
        selection.apply(.extend, to: "a", order: order)
        #expect(selection.selectedIds == ["a", "b"])
        #expect(selection.anchorId == "b")
    }

    @Test func shiftClickWithoutAnAnchorStartsASelection() {
        var selection = MessageSelection()
        selection.apply(.extend, to: "c", order: order)
        #expect(selection.selectedIds == ["c"])
        #expect(selection.anchorId == "c")
    }

    @Test func shiftClickWithAnAnchorThatLeftTheOrderStartsASelection() {
        var selection = MessageSelection()
        selection.apply(.select, to: "b", order: order)
        selection.apply(.extend, to: "d", order: ["e", "d", "c"])
        #expect(selection.selectedIds == ["d"])
    }

    @Test func commandClickTogglesOneMessage() {
        var selection = MessageSelection()
        selection.apply(.select, to: "a", order: order)
        selection.apply(.toggle, to: "c", order: order)
        #expect(selection.selectedIds == ["a", "c"])
        #expect(selection.anchorId == "c")
        selection.apply(.toggle, to: "c", order: order)
        #expect(selection.selectedIds == ["a"])
        #expect(selection.anchorId == nil)
    }

    @Test func clearRemovesTheSelectionAndTheAnchor() {
        var selection = MessageSelection()
        selection.apply(.select, to: "a", order: order)
        selection.clear()
        #expect(selection.isEmpty)
        #expect(selection.anchorId == nil)
    }

    @Test func retainDropsMessagesThatLeftTheTimeline() {
        var selection = MessageSelection()
        selection.apply(.select, to: "b", order: order)
        selection.apply(.extend, to: "d", order: order)
        let unchanged = selection.retain(Set(order))
        #expect(!unchanged)
        let changed = selection.retain(["c", "d", "e"])
        #expect(changed)
        #expect(selection.selectedIds == ["c", "d"])
        #expect(selection.anchorId == nil)
    }
}

/// MATRIX-113: Copy Messages in the shared action model.
struct MessageCopyMessagesActionTests {
    private let subject = MessageActionSubject(
        content: .text,
        isOwn: false,
        eventId: "$event",
        canBeRepliedTo: true,
        isPinned: false,
        copyableText: "hello"
    )

    private func actions(on surface: MessageActionSurface, selection: Bool, subject: MessageActionSubject?) -> [MessageActionItem] {
        MessageActionModel.items(for: subject, on: surface, hasMessageSelection: selection)
    }

    @Test func noSurfaceOffersItWithoutASelection() {
        for surface in MessageActionSurface.allCases {
            #expect(!actions(on: surface, selection: false, subject: subject).contains { $0.action == .copyMessages })
        }
    }

    @Test func menusOfferItEnabledWithASelection() {
        for surface in [MessageActionSurface.contextMenu, .editMenu] {
            let item = actions(on: surface, selection: true, subject: subject).first { $0.action == .copyMessages }
            #expect(item?.isEnabled == true)
            #expect(item?.section == .copy)
        }
    }

    @Test func itHeadsTheCopyGroup() {
        let menu = actions(on: .contextMenu, selection: true, subject: subject).map(\.action)
        let index = menu.firstIndex(of: .copyMessages)
        #expect(index.map { menu[$0 + 1] } == .copyText)
    }

    @Test func hoverRowNeverOffersIt() {
        #expect(!actions(on: .hoverRow, selection: true, subject: subject).contains { $0.action == .copyMessages })
    }

    @Test func editMenuOffersItWithoutASingleTarget() {
        let items = actions(on: .editMenu, selection: true, subject: nil)
        #expect(items.filter(\.isEnabled).map(\.action) == [.copyMessages])
    }

    @Test func itIsNotAMediaAction() {
        #expect(!MessageAction.copyMessages.isMediaAction)
    }
}

/// MATRIX-113: a selection is the Edit menu's target before the hover.
@MainActor
struct MessageActionTargetSlotSelectionTests {
    private struct Report: Equatable {
        let key: String
        let gesture: MessageSelectionGesture
    }

    private final class Recorder {
        var performed: [String: [MessageAction]] = [:]
        var gestures: [Report] = []
        var copies = 0
    }

    private func target(_ key: String, isPinned: Bool = false, recorder: Recorder) -> MessageActionTarget {
        let subject = MessageActionSubject(
            content: .text,
            isOwn: true,
            eventId: "$\(key)",
            canBeRepliedTo: true,
            isPinned: isPinned,
            copyableText: "body"
        )
        return MessageActionTarget(key: key, subject: subject) { action in
            recorder.performed[key, default: []].append(action)
        }
    }

    @Test func selectReportsTheGestureToTheContainer() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.selectionGestureHandler = { key, gesture in
            recorder.gestures.append(Report(key: key, gesture: gesture))
        }
        slot.select(.extend, on: target("a", recorder: recorder))
        #expect(recorder.gestures == [Report(key: "a", gesture: .extend)])
    }

    @Test func aSingleSelectionIsTheTargetBeforeTheHover() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.select(.select, on: target("a", recorder: recorder))
        slot.showSelection(keys: ["a"]) { recorder.copies += 1 }
        slot.offer(target("b", recorder: recorder))

        #expect(slot.hasMessageSelection)
        #expect(slot.editMenuTarget?.key == "a")
        slot.perform(.reply)
        #expect(recorder.performed == ["a": [.reply]])
        #expect(slot.editMenuItems.first { $0.action == .copyMessages }?.isEnabled == true)
    }

    @Test func aMultipleSelectionDisablesTheSingleMessageItems() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.offer(target("b", recorder: recorder))
        slot.select(.extend, on: target("a", recorder: recorder))
        slot.showSelection(keys: ["a", "b"]) { recorder.copies += 1 }

        #expect(slot.editMenuTarget == nil)
        #expect(slot.editMenuItems.filter(\.isEnabled).map(\.action) == [.copyMessages])
        slot.perform(.reply)
        #expect(recorder.performed.isEmpty)
    }

    @Test func copyMessagesRunsTheContainerCopy() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.showSelection(keys: ["a", "b"]) { recorder.copies += 1 }
        slot.perform(.copyMessages)
        slot.copySelection()
        #expect(recorder.copies == 2)
    }

    @Test func clearingTheSelectionGivesTheMenuBackToTheHover() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.offer(target("b", recorder: recorder))
        slot.select(.select, on: target("a", recorder: recorder))
        slot.showSelection(keys: ["a"]) { recorder.copies += 1 }
        slot.clearSelection()

        #expect(!slot.hasMessageSelection)
        #expect(slot.editMenuTarget?.key == "b")
        #expect(!slot.editMenuItems.contains { $0.action == .copyMessages })
        slot.perform(.copyMessages)
        #expect(recorder.copies == 0)
    }

    @Test func anEmptySelectionClears() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.showSelection(keys: ["a"]) { recorder.copies += 1 }
        slot.showSelection(keys: []) { recorder.copies += 1 }
        #expect(!slot.hasMessageSelection)
    }

    @Test func refreshAndWithdrawFollowTheSelectedMessage() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.select(.select, on: target("a", recorder: recorder))
        slot.showSelection(keys: ["a"]) { recorder.copies += 1 }

        // A local echo gets its event ID while it is selected.
        slot.refresh(replacing: "a", with: target("a2", isPinned: true, recorder: recorder))
        #expect(slot.editMenuTarget?.key == "a2")
        #expect(slot.editMenuItems.contains { $0.action == .unpin })

        // Its row leaves the screen: it stays selected, with no single target.
        slot.withdraw(key: "a2")
        #expect(slot.hasMessageSelection)
        #expect(slot.editMenuTarget == nil)
        #expect(slot.editMenuItems.filter(\.isEnabled).map(\.action) == [.copyMessages])
    }
}
