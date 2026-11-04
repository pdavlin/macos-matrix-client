import Foundation
import Observation
import OSLog

/// Pure send rules for the iOS composer (MATRIX-86).
enum ComposerRules {
    /// The body the composer sends for `text`: surrounding whitespace and
    /// newlines are trimmed, inner newlines are kept. Nil when nothing is left.
    static func outgoingBody(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The send button is enabled when there is a body and no send is in
    /// flight.
    static func canSend(text: String, isSending: Bool) -> Bool {
        !isSending && outgoingBody(text) != nil
    }
}

/// The message a send will reply to, reduced to what the preview bar draws.
struct ComposerReply: Equatable {
    /// The target's event or transaction id: a new target is a new preview.
    let id: String
    let senderName: String
    let preview: String
}

/// What the composer sends through (MATRIX-86). The live target wraps the
/// room's `LiveTimeline`; the DEBUG fixture has its own.
@MainActor
protocol ComposerTarget: AnyObject {
    /// The current reply target, or nil for a plain message.
    var reply: ComposerReply? { get }
    func cancelReply()
    /// Enqueues `body`, as a reply when `reply` is set. Throws when the
    /// message never reached the send queue. A later failure surfaces on the
    /// local echo instead.
    func send(body: String) async throws
    /// The user typed into a non-empty composer.
    func noteTyping() async
}

/// The composer's text and send state (MATRIX-86).
@MainActor @Observable
final class ComposerModel {
    var text = ""
    private(set) var isSending = false

    var canSend: Bool {
        ComposerRules.canSend(text: text, isSending: isSending)
    }

    /// Sends the text through `target`.
    ///
    /// The field clears at once, so the next message can start while this one
    /// is enqueued. When the enqueue fails, nothing reached the send queue, so
    /// no local echo carries a retry: the text comes back unless the user has
    /// typed something new, and the reply target stays.
    func send(to target: ComposerTarget) async {
        guard !isSending, let body = ComposerRules.outgoingBody(text) else { return }
        let draft = text
        isSending = true
        text = ""
        defer { isSending = false }
        do {
            try await target.send(body: body)
            target.cancelReply()
        } catch {
            Logger.composerIOS.error("failed to enqueue message: \(error)")
            if text.isEmpty {
                text = draft
            }
        }
    }
}

extension Logger {
    static let composerIOS = Logger(subsystem: "io.davlin.matrixclient.ios", category: "composer")
}
