import Foundation
import MatrixRustSDK
import Models
import OSLog

/// One message that waits for the delete confirmation (MATRIX-110, M2-B3).
public struct MessageRedactionRequest: Identifiable {
    /// The event ID, or the transaction ID of a local echo. The SDK redacts
    /// a sent event and aborts the send of a local echo.
    public let itemId: MatrixRustSDK.EventOrTransactionId
    /// Whether the signed-in account sent the message. The sheet words its
    /// note from it.
    public let isOwn: Bool

    public var id: String {
        itemId.id
    }

    public init(itemId: MatrixRustSDK.EventOrTransactionId, isOwn: Bool) {
        self.itemId = itemId
        self.isOwn = isOwn
    }
}

// MARK: - Redaction (MATRIX-110)

public extension LiveTimeline {
    /// Asks for the delete confirmation of a message. Nothing is sent until
    /// `confirmRedaction(_:reason:)`.
    ///
    /// - Parameters:
    ///   - itemId: The message's event or transaction ID.
    ///   - isOwn: Whether the signed-in account sent it.
    func requestRedaction(of itemId: MatrixRustSDK.EventOrTransactionId, isOwn: Bool) {
        pendingRedaction = MessageRedactionRequest(itemId: itemId, isOwn: isOwn)
    }

    /// Closes the confirmation without a redaction.
    func cancelRedaction() {
        pendingRedaction = nil
    }

    /// Closes the confirmation and redacts the message.
    ///
    /// A failure goes to `redactionFailure`, for example when the power
    /// levels changed after the menu opened and the homeserver refuses.
    ///
    /// - Parameters:
    ///   - request: The confirmed request.
    ///   - reason: The typed reason. Empty or blank text sends no reason.
    func confirmRedaction(_ request: MessageRedactionRequest, reason: String) {
        pendingRedaction = nil
        guard let timeline else {
            Logger.liveTimeline.error("redaction of \(request.id) with no timeline")
            return
        }
        let reason = MessageRedaction.normalizedReason(reason)
        Task { [weak self] in
            do {
                try await timeline.redactEvent(eventOrTransactionId: request.itemId, reason: reason)
                Logger.liveTimeline.info("redacted \(request.id)")
            } catch {
                Logger.liveTimeline.error("failed to redact \(request.id): \(error)")
                self?.redactionFailure = error.localizedDescription
            }
        }
    }
}
