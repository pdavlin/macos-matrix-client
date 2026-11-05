import Foundation
import Observation

/// The steps of one forward (MATRIX-112, M2-B5): pick a room, confirm, send.
///
/// The room view shows two sheets, one after the other: the quick switcher
/// in picker mode while `picking` is set, and the confirmation while
/// `confirming` is set. A sheet or an alert can open only after the sheet
/// before it has closed, so a pick and a failure are held back until the
/// sheet reports that it closed (`sheetDidClose()`).
///
/// Generic over the request and the target, so the rules run in unit tests
/// with no SDK types. `Core` uses it with the SDK message and room.
///
/// Usage:
/// ```swift
/// flow.start(request)              // the picker opens
/// flow.pick(room)                  // the picker closes
/// flow.sheetDidClose()             // the confirmation opens
/// await flow.confirm { request, room in try await send(request, to: room) }
/// ```
@MainActor @Observable
public final class MessageForwardFlow<Request, Target> {
    /// One forward in one step. The ID stays the same across the steps.
    public struct Step: Identifiable {
        public let id: UUID
        public let request: Request
        /// Nil while the room is not picked yet.
        public let target: Target?
    }

    /// The forward that waits for a room. The picker shows while it is set.
    public private(set) var picking: Step?
    /// The forward that waits for the confirmation. Its target is set. The
    /// confirmation shows while it is set.
    public private(set) var confirming: Step?
    /// Whether the confirmed forward is still on its way to the send queue.
    /// The confirmation shows a spinner and cannot be cancelled meanwhile.
    public private(set) var isSending = false
    /// Why the last forward failed, or nil. The room view shows it in an
    /// alert and clears it with `clearFailure()`.
    public private(set) var failure: String?

    /// A pick that waits for the picker to close.
    @ObservationIgnored private var picked: Step?
    /// A failure that waits for its sheet to close.
    @ObservationIgnored private var pendingFailure: String?

    public init() {}

    /// Starts a forward: the picker opens. Any forward that was not
    /// confirmed is dropped.
    ///
    /// - Parameter request: The message to forward.
    /// - Returns: False, and nothing changes, while a confirmed forward is
    ///   still sending.
    @discardableResult
    public func start(_ request: Request) -> Bool {
        guard !isSending else { return false }
        picked = nil
        pendingFailure = nil
        confirming = nil
        failure = nil
        picking = Step(id: UUID(), request: request, target: nil)
        return true
    }

    /// Records the picked room and closes the picker. The confirmation
    /// opens when the picker reports that it closed (`sheetDidClose()`).
    ///
    /// - Parameter target: The room to forward to.
    public func pick(_ target: Target) {
        guard let picking else { return }
        picked = Step(id: picking.id, request: picking.request, target: target)
        self.picking = nil
    }

    /// Closes the picker with no pick, for example on Escape. A pick that
    /// was made stays and opens the confirmation in `sheetDidClose()`.
    public func dismissPicker() {
        picking = nil
    }

    /// A forward sheet has closed. Opens the confirmation if a room was
    /// picked, else shows a held-back failure.
    public func sheetDidClose() {
        picking = nil
        if let picked {
            self.picked = nil
            confirming = picked
        } else if let pendingFailure {
            self.pendingFailure = nil
            failure = pendingFailure
        }
    }

    /// Closes the confirmation with no send. Does nothing while the
    /// confirmed forward sends.
    public func cancel() {
        guard !isSending else { return }
        picking = nil
        picked = nil
        confirming = nil
    }

    /// Ends the forward with an error before the confirmation, for example
    /// when the picked room cannot be found. If a sheet is open, the alert
    /// waits until it closes.
    ///
    /// - Parameter message: The text for the alert.
    public func fail(_ message: String) {
        let sheetIsOpen = picking != nil || confirming != nil
        picking = nil
        picked = nil
        confirming = nil
        if sheetIsOpen {
            pendingFailure = message
        } else {
            failure = message
        }
    }

    /// Clears the failure after the alert closes.
    public func clearFailure() {
        failure = nil
    }

    /// Sends the confirmed forward. The confirmation stays open, with a
    /// spinner, until `send` returns, then closes. An error goes to
    /// `failure` when the confirmation has closed (`sheetDidClose()`).
    ///
    /// - Parameter send: Puts the forward into the target room's send queue.
    ///   It returns when the SDK has the message, not when it is delivered.
    public func confirm(send: @MainActor (_ request: Request, _ target: Target) async throws -> Void) async {
        guard !isSending, let confirming, let target = confirming.target else { return }
        isSending = true
        do {
            try await send(confirming.request, target)
        } catch {
            pendingFailure = error.localizedDescription
        }
        isSending = false
        self.confirming = nil
    }
}
