import Foundation
import Models

/// An event as the container sees it.
///
/// A value type, unlike the real binding's object. Nothing in the three
/// container files depends on reference identity: rows are keyed by
/// `TimelineUniqueId` and heights by the row's `uniqueId` string.
public struct EventTimelineItem: Models.EventTimelineItem, Identifiable, Sendable {
    public let eventOrTransactionId: EventOrTransactionId
    public let sender: String
    public let senderDisplayName: String?
    public let date: Date
    public var content: TimelineItemContent

    public init(
        eventOrTransactionId: EventOrTransactionId,
        sender: String,
        senderDisplayName: String?,
        date: Date,
        content: TimelineItemContent
    ) {
        self.eventOrTransactionId = eventOrTransactionId
        self.sender = sender
        self.senderDisplayName = senderDisplayName
        self.date = date
        self.content = content
    }

    public var id: EventOrTransactionId { eventOrTransactionId }

    public var isRemote: Bool {
        true
    }

    public var isOwn: Bool {
        false
    }

    public var isEditable: Bool {
        false
    }

    public var sendState: LocalSendState? {
        nil
    }

    public var localCreatedAt: UInt64? {
        nil
    }

    public var userReadReceipts: [String: Receipt] {
        [:]
    }

    public var canBeRepliedTo: Bool {
        true
    }

    public var senderProfileDetails: ProfileDetails {
        .ready(displayName: senderDisplayName, displayNameAmbiguous: false, avatarUrl: nil)
    }

    public var userId: String { sender }
    public var displayName: String? { senderDisplayName }
    public var avatarUrl: String? { nil }
}

/// One entry of `LiveTimeline.displayItems`: either an event or a virtual row.
///
/// Not `Sendable`: `Models.VirtualTimelineItem` is not, and the container is
/// `@MainActor` throughout, so nothing here ever crosses an isolation domain.
public struct TimelineItem {
    private let identifier: TimelineUniqueId
    private let event: EventTimelineItem?
    private let virtual: VirtualTimelineItem?

    public init(event: EventTimelineItem, uniqueId: TimelineUniqueId) {
        self.identifier = uniqueId
        self.event = event
        self.virtual = nil
    }

    public init(virtual: VirtualTimelineItem, uniqueId: TimelineUniqueId) {
        self.identifier = uniqueId
        self.event = nil
        self.virtual = virtual
    }

    public func uniqueId() -> TimelineUniqueId {
        identifier
    }

    public func asEvent() -> EventTimelineItem? {
        event
    }

    public func asVirtual() -> VirtualTimelineItem? {
        virtual
    }
}
