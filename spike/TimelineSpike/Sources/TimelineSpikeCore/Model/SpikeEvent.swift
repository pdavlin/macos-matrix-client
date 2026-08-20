import Foundation

/// The identity of a synthetic event.
///
/// `rawValue` is the event's position on an infinite, ordered index line. The initial
/// window occupies `0 ..< initialEventCount`; back-pagination walks into negative indices.
/// Because the loaded window is always contiguous, an event's array position is
/// `rawValue - oldestIndex`, so the store needs no identifier lookup table.
public struct EventID: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    public let rawValue: Int

    public init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    public var description: String {
        "$spike\(rawValue)"
    }

    public static func < (lhs: EventID, rhs: EventID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// A synthetic sender. Senders exist only to drive avatar and run-grouping layout.
public struct SpikeSender: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public let displayName: String
    public let avatarHue: Double

    public init(id: String, displayName: String, avatarHue: Double) {
        self.id = id
        self.displayName = displayName
        self.avatarHue = avatarHue
    }

    /// A fixed roster. Keep it stable: changing it changes every generated timeline.
    public static let roster: [SpikeSender] = [
        SpikeSender(id: "@ada", displayName: "Ada Lovelace", avatarHue: 0.02),
        SpikeSender(id: "@grace", displayName: "Grace Hopper", avatarHue: 0.13),
        SpikeSender(id: "@alan", displayName: "Alan Turing", avatarHue: 0.27),
        SpikeSender(id: "@katherine", displayName: "Katherine Johnson", avatarHue: 0.41),
        SpikeSender(id: "@margaret", displayName: "Margaret Hamilton", avatarHue: 0.55),
        SpikeSender(id: "@barbara", displayName: "Barbara Liskov", avatarHue: 0.68),
        SpikeSender(id: "@radia", displayName: "Radia Perlman", avatarHue: 0.79),
        SpikeSender(id: "@bridge", displayName: "signalbot (bridge)", avatarHue: 0.91)
    ]
}

/// A text body. `lineCount` is the authored target, not a measured line count: real
/// wrapping depends on the render width, so treat it as the height knob it is.
public struct TextBody: Sendable, Equatable, Codable {
    public var paragraphs: [String]
    public var lineCount: Int

    public init(paragraphs: [String], lineCount: Int) {
        self.paragraphs = paragraphs
        self.lineCount = lineCount
    }

    public var text: String {
        paragraphs.joined(separator: "\n\n")
    }
}

/// An image placeholder. No bytes are decoded; the renderer draws a shape at the given
/// aspect ratio so variable-height media participates in layout.
public struct ImagePlaceholder: Sendable, Equatable, Codable {
    /// Width divided by height.
    public var aspectRatio: Double
    /// Intrinsic width in points, before the renderer clamps it to the bubble width.
    public var intrinsicWidth: Double
    public var hue: Double
    public var caption: String?

    public init(aspectRatio: Double, intrinsicWidth: Double, hue: Double, caption: String?) {
        self.aspectRatio = aspectRatio
        self.intrinsicWidth = intrinsicWidth
        self.hue = hue
        self.caption = caption
    }
}

public enum EventContent: Sendable, Equatable, Codable {
    case text(TextBody)
    case image(ImagePlaceholder)

    public var isText: Bool {
        if case .text = self { return true }
        return false
    }

    public var textBody: TextBody? {
        if case .text(let body) = self { return body }
        return nil
    }
}

/// One aggregated reaction key with its tally.
public struct Reaction: Sendable, Equatable, Codable, Identifiable {
    public let key: String
    public var count: Int

    public init(key: String, count: Int) {
        self.key = key
        self.count = count
    }

    public var id: String { key }
}

/// A synthetic timeline event.
///
/// Only `content`, `reactions` and `editCount` are mutable. Identity, sender and timestamp
/// are fixed for the life of the event: the mutation driver must never reorder the
/// timeline, because that would invalidate the anchor-drift measurement.
public struct SpikeEvent: Identifiable, Sendable, Equatable, Codable {
    public let id: EventID
    public let sender: SpikeSender
    public let timestamp: Date
    public var content: EventContent
    public var reactions: [Reaction]
    public var editCount: Int

    public init(
        id: EventID,
        sender: SpikeSender,
        timestamp: Date,
        content: EventContent,
        reactions: [Reaction] = [],
        editCount: Int = 0
    ) {
        self.id = id
        self.sender = sender
        self.timestamp = timestamp
        self.content = content
        self.reactions = reactions
        self.editCount = editCount
    }
}

/// An event plus the layout flags the store derives from its neighbours.
///
/// The store owns grouping and day separators so that both timeline candidates render the
/// same structure. A candidate that recomputed grouping itself could quietly measure a
/// different workload.
public struct TimelineItem: Identifiable, Sendable, Equatable {
    public var event: SpikeEvent
    /// `true` when the item shows an avatar and a sender header.
    public var startsSenderRun: Bool
    /// The start of day when this item opens a new calendar day, otherwise `nil`.
    public var daySeparator: Date?

    public init(event: SpikeEvent, startsSenderRun: Bool = true, daySeparator: Date? = nil) {
        self.event = event
        self.startsSenderRun = startsSenderRun
        self.daySeparator = daySeparator
    }

    public var id: EventID { event.id }
}
