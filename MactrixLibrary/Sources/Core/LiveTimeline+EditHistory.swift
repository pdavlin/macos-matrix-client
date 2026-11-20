import Foundation
import MatrixRustSDK
import Models
import OSLog

/// A request to show the edit history of one message (MATRIX-209).
public struct EditHistoryRequest: Equatable, Sendable {
    /// The edited message. The SDK reads its versions by event ID.
    public let eventId: String

    public init(eventId: String) {
        self.eventId = eventId
    }
}

// MARK: - Edit history (MATRIX-209)

public extension LiveTimeline {
    /// Asks the timeline container to show the edit history popover on a
    /// message.
    ///
    /// The right-click "Show Edit History" and a click on the "(edited)"
    /// mark both end here. The container scrolls the row into view if
    /// needed and shows the popover on it. A new request closes a popover
    /// that is open.
    func requestEditHistory(forEventId eventId: String) {
        Logger.liveTimeline.info("edit history requested for \(eventId)")
        editHistoryRequests.send(EditHistoryRequest(eventId: eventId))
    }

    /// Reads the versions of an edited message from the SDK, newest first.
    ///
    /// The SDK finds the edits and decrypts them in an encrypted room. A
    /// version it cannot decrypt comes back as an unable-to-decrypt item.
    ///
    /// - Parameter eventId: The edited message.
    /// - Returns: The versions, or `.failed` when the SDK call fails.
    func editHistory(of eventId: String) async -> EditHistoryState<MatrixRustSDK.MessageContent> {
        guard let timeline else {
            Logger.liveTimeline.error("edit history: the timeline has not loaded")
            return .failed
        }
        do {
            let revisions = try await timeline.editRevisions(eventId: eventId)
            typealias Version = Models.EditHistoryVersion<MatrixRustSDK.MessageContent>
            return .loaded(Version.newestFirst(revisions.map { (body: Version.Body($0.content), timestamp: $0.timestamp) }))
        } catch {
            Logger.liveTimeline.error("failed to read the edit history: \(String(describing: error), privacy: .public)")
            return .failed
        }
    }
}

public extension Models.EditHistoryVersion.Body where Message == MatrixRustSDK.MessageContent {
    /// The body of one SDK revision. Every switch is exhaustive with no
    /// `default`, so a new SDK case has to be given a body here.
    init(_ content: MatrixRustSDK.TimelineItemContent) {
        switch content {
        case let .msgLike(content: msgLike):
            switch msgLike.kind {
            case let .message(content: message):
                self = .message(message)
            case let .unableToDecrypt(msg: encrypted):
                self = .unableToDecrypt(Models.UnableToDecryptCause(encrypted: encrypted))
            case .sticker, .poll, .redacted, .other, .liveLocation:
                self = .other(msgLike.kind.description)
            }
        case .callInvite, .rtcNotification, .roomMembership, .profileChange, .state, .failedToParseMessageLike, .failedToParseState:
            self = .other(content.description)
        }
    }
}
