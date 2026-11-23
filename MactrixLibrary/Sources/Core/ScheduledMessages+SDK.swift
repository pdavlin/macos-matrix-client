import Foundation
import MatrixRustSDK
import Models

/// The SDK calls of Send Later (MATRIX-212).
///
/// Verified in `docs/ffi/matrix_sdk_ffi.swift` (26.11.11):
/// - `Room.sendDelayedEvent(eventType:content:delayMs:requestConfigOverride:)
///   async throws -> String` (lines 11230, 13427). The string is the
///   `delay_id`. An encrypted room's content is encrypted at schedule time.
/// - `Client.updateDelayedEvent(delayId:action:requestConfigOverride:)
///   async throws` (lines 1765, 4331), `DelayedEventUpdateAction`
///   (line 34843).
/// - `ClientError.MatrixApi(kind:code:msg:details:)` (line 34021) and
///   `ErrorKind` (line 35487): `limitExceeded(retryAfterMs:)`, `forbidden`,
///   `notFound`, `unrecognized`, `custom(errcode:)`.
@MainActor
final class LiveScheduledMessageTransport: ScheduledMessageTransport {
    private let client: ClientProtocol

    init(client: ClientProtocol) {
        self.client = client
    }

    func readRegistry() async throws -> String? {
        try await client.accountData(eventType: ScheduledMessageDocument.eventType)
    }

    func writeRegistry(_ json: String) async throws {
        try await client.setAccountData(eventType: ScheduledMessageDocument.eventType, content: json)
    }

    func scheduleMessage(roomId: String, contentJSON: String, delayMs: UInt64) async throws(ScheduledMessageFailure) -> String {
        let room: MatrixRustSDK.Room?
        do {
            room = try client.getRoom(roomId: roomId)
        } catch {
            throw Self.failure(from: error)
        }
        guard let room else { throw .roomUnavailable }
        do {
            return try await room.sendDelayedEvent(
                eventType: ScheduledMessageContent.eventType,
                content: contentJSON,
                delayMs: delayMs
            )
        } catch {
            throw Self.failure(from: error)
        }
    }

    func updateDelayedEvent(delayId: String, update: ScheduledMessageUpdate) async throws(ScheduledMessageFailure) {
        let action: DelayedEventUpdateAction = switch update {
        case .send: .send
        case .cancel: .cancel
        }
        do {
            try await client.updateDelayedEvent(delayId: delayId, action: action, requestConfigOverride: nil)
        } catch {
            throw Self.failure(from: error)
        }
    }

    /// The Send Later failure for an SDK error. The codes are in
    /// docs/research/send-later.md §3.
    nonisolated static func failure(from error: any Error) -> ScheduledMessageFailure {
        guard let clientError = error as? ClientError else {
            return .other(String(describing: error))
        }
        switch clientError {
        case let .MatrixApi(kind, code, msg, _):
            switch kind {
            case let .limitExceeded(retryAfterMs):
                return .rateLimited(retryAfter: retryAfterMs.map { TimeInterval($0) / 1000 })
            case .forbidden:
                return .forbidden
            case .notFound:
                return .notFound
            case .unrecognized:
                return .unsupported
            case let .custom(errcode):
                return .custom(errcode: errcode, message: msg)
            default:
                // A delay-too-large code the SDK maps to a known kind
                // still carries its code.
                return .custom(errcode: code, message: msg)
            }
        case let .Generic(msg, _):
            return .other(msg)
        case let .ContentScanner(_, info):
            return .other(info)
        }
    }
}
