import Models
import Testing

/// MATRIX-108: the Edit menu's target is the hovered or focused message.
@MainActor
struct MessageActionTargetSlotTests {
    private final class Recorder {
        var performed: [String: [MessageAction]] = [:]
    }

    private func target(
        _ key: String,
        content: MessageActionSubject.Content = .text,
        isPinned: Bool = false,
        recorder: Recorder
    ) -> MessageActionTarget {
        let subject = MessageActionSubject(
            content: content,
            isOwn: false,
            eventId: "$\(key)",
            canBeRepliedTo: true,
            isPinned: isPinned,
            copyableText: content == .text ? "body" : nil
        )
        return MessageActionTarget(key: key, subject: subject) { action in
            recorder.performed[key, default: []].append(action)
        }
    }

    @Test func startsWithEveryItemDisabled() {
        let slot = MessageActionTargetSlot()
        #expect(slot.target == nil)
        #expect(slot.editMenuItems.allSatisfy { !$0.isEnabled })
    }

    @Test func performRunsOnTheOfferedTarget() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.offer(target("a", recorder: recorder))
        slot.offer(target("b", recorder: recorder))
        slot.perform(.copyLink)
        #expect(recorder.performed == ["b": [.copyLink]])
    }

    @Test func performWithoutATargetDoesNothing() {
        let slot = MessageActionTargetSlot()
        slot.perform(.reply)
        #expect(slot.target == nil)
    }

    @Test func withdrawClearsOnlyTheMatchingTarget() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.offer(target("a", recorder: recorder))
        slot.withdraw(key: "b")
        #expect(slot.target?.key == "a")
        slot.withdraw(key: "a")
        #expect(slot.target == nil)
        #expect(slot.editMenuItems.allSatisfy { !$0.isEnabled })
    }

    @Test func refreshReplacesOnlyTheMatchingTarget() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.offer(target("a", recorder: recorder))
        slot.refresh(replacing: "b", with: target("b", isPinned: true, recorder: recorder))
        #expect(slot.target?.key == "a")

        // A local echo gets its event ID: the old key names the new target.
        slot.refresh(replacing: "a", with: target("a2", isPinned: true, recorder: recorder))
        #expect(slot.target?.key == "a2")
        #expect(slot.editMenuItems.last?.action == .unpin)
    }

    @Test func editMenuItemsFollowTheTarget() {
        let slot = MessageActionTargetSlot()
        let recorder = Recorder()
        slot.offer(target("text", recorder: recorder))
        let allEnabled = slot.editMenuItems.allSatisfy(\.isEnabled)
        #expect(allEnabled)
        slot.offer(target("image", content: .image, recorder: recorder))
        #expect(slot.editMenuItems.first { $0.action == .copyText }?.isEnabled == false)
    }
}
