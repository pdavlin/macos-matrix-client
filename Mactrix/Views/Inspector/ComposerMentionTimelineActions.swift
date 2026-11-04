import Core
import Models
import UI

/// The user profile "Timeline" actions for the selected room (MATRIX-105).
///
/// "Mention" asks the room composer to insert a chip for the user, through
/// `LiveTimeline.pendingComposerMention`. "Jump to read receipt" has no
/// implementation yet, so its button shows as disabled.
@MainActor
struct ComposerMentionTimelineActions: UserProfileTimelineActions {
    /// The timeline whose composer gets the chip.
    let timeline: LiveTimeline
    /// The user to mention, with the name to show on the chip.
    let target: MentionTarget

    var canJumpToReadReceipt: Bool {
        false
    }

    func jumpToReadReceipt() {}

    func mentionUser() {
        timeline.pendingComposerMention = target
    }
}
