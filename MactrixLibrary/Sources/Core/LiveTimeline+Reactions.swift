import Foundation
import MatrixRustSDK
import Models
import OSLog

/// A request to show the reaction picker on one message (MATRIX-138).
public struct ReactionPickerRequest: Equatable {
    /// The message the picked emoji reacts to.
    public let eventId: MatrixRustSDK.EventOrTransactionId
    /// The hover row buttons after the picker button, toward the trailing
    /// edge, so the popover can point at the button
    /// (`UI.HoverActionBarGeometry.buttonsAfter(_:in:)`). Nil when the hover
    /// row has no picker button.
    public let hoverButtonsAfterPicker: Int?

    public init(eventId: MatrixRustSDK.EventOrTransactionId, hoverButtonsAfterPicker: Int?) {
        self.eventId = eventId
        self.hoverButtonsAfterPicker = hoverButtonsAfterPicker
    }
}

// MARK: - Reactions (MATRIX-111, MATRIX-138)

public extension LiveTimeline {
    /// Asks the timeline container to show the reaction picker on a message.
    ///
    /// The hover row's picker button, the right-click "Add Reaction…", and
    /// the Edit menu "Add Reaction…" all end here. The container scrolls the
    /// row into view if needed and shows the picker over it. A new request
    /// closes a picker that is open.
    ///
    /// - Parameters:
    ///   - eventId: The message.
    ///   - hoverButtonsAfterPicker: See `ReactionPickerRequest`.
    func requestReactionPicker(for eventId: MatrixRustSDK.EventOrTransactionId, hoverButtonsAfterPicker: Int?) {
        Logger.liveTimeline.info("reaction picker requested for \(eventId.id)")
        reactionPickerRequests.send(ReactionPickerRequest(eventId: eventId, hoverButtonsAfterPicker: hoverButtonsAfterPicker))
    }

    /// Toggles the own reaction `key` on a message, and records an added
    /// reaction as a use of the emoji.
    ///
    /// The one path for every reaction toggle: the hover row, the menus, a
    /// reaction pill, and the picker (in the row or in the timeline
    /// controller's popover). Every added reaction counts as a use of the
    /// emoji in the account's recent list (D-3). Removing a reaction is not
    /// a use. The SDK owns the toggle.
    ///
    /// - Parameters:
    ///   - key: The reaction key, usually one emoji.
    ///   - itemId: The message.
    ///   - client: The client whose recent-emoji list records the use. Nil
    ///     records nothing.
    func toggleReaction(key: String, on itemId: MatrixRustSDK.EventOrTransactionId, recordingUseIn client: MatrixClient?) async {
        guard let timeline else {
            Logger.liveTimeline.error("toggle reaction: the timeline has not loaded")
            return
        }
        do {
            let reactionWasAdded = try await timeline.toggleReaction(itemId: itemId, key: key)
            Logger.liveTimeline.debug("reaction \(reactionWasAdded ? "added" : "removed"): \(key)")
            if reactionWasAdded {
                client?.recordRecentEmoji(key)
            }
        } catch {
            Logger.liveTimeline.error("failed to toggle reaction: \(String(describing: error), privacy: .public)")
        }
    }
}
