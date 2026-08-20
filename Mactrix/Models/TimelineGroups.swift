import Foundation
import MatrixRustSDK
import OSLog
import SwiftUI

public struct TimelineGroups: Hashable {
    public var groups: [TimelineGroup] = []
    public var version: Int = 0

    public mutating func insertEnd(timelineItem item: TimelineItem, withVersion overrideVersion: Int? = nil) {
        if overrideVersion == nil {
            version += 1
        }

        let version = if let overrideVersion {
            overrideVersion
        } else {
            self.version
        }

        if let event = item.asEvent() {
            if case let .msgLike(content: content) = event.content {
                if case let .messages(messages, id, _) = groups.last, messages[0].event.sender == event.sender {
                    groups[groups.count - 1] = .messages(messages: messages + [TimelineGroup.Message(id: item.uniqueId().id, event: event, content: content)], id: id, version: version)
                    return
                }
            } else {
                if case let .stateChanges(events: events, id, _) = groups.last {
                    groups[groups.count - 1] = .stateChanges(events: events + [TimelineGroup.Event(id: item.uniqueId().id, event: event)], id: id, version: version)
                    return
                }
            }
        }

        groups.append(TimelineGroup(timelineItem: item, version: version))
    }

    public mutating func updateItems(items: [TimelineItem], updatedIds: Set<String>) {
        let oldVersions = versions

        groups.removeAll(keepingCapacity: true)
        version += 1
        for item in items {
            if updatedIds.contains(item.uniqueId().id) {
                insertEnd(timelineItem: item)
            } else {
                insertEnd(timelineItem: item, withVersion: oldVersions[item.uniqueId().id])
            }
        }
    }

    public mutating func clear() {
        version += 1
        groups.removeAll()
    }

    public mutating func removeLast() {
        version += 1
        groups.removeLast()
    }

    public func indexGroups(_ i: Int) -> (Int, Int)? {
        var count = 0
        for group in groups {
            count += group.count
            if count > i {
                return (i, count - i - 1)
            }
        }
        return nil
    }

    var versions: [String: Int] {
        var result = [String: Int]()

        for group in groups {
            switch group {
            case let .messages(messages, _, version):
                for message in messages {
                    result[message.event.eventOrTransactionId.id] = version
                }
            case let .stateChanges(events, _, version):
                for event in events {
                    result[event.id] = version
                }
            case let .virtual(_, id, version):
                result[id] = version
            }
        }

        return result
    }
}

public enum TimelineGroup: Hashable, Identifiable {
    /// Event timeline items that are of type MsgLike, grouped by the same sender
    case messages(messages: [Message], id: String, version: Int)
    /// Event timeline items that are not of type MsgLike, all grouped
    case stateChanges(events: [Event], id: String, version: Int)
    case virtual(item: VirtualTimelineItem, id: String, version: Int)

    public struct Message: Identifiable {
        public let id: String
        public let event: EventTimelineItem
        public let content: MsgLikeContent
    }

    public struct Event: Identifiable {
        public let id: String
        public let event: EventTimelineItem
    }

    public var id: String {
        switch self {
        case let .messages(_, id, _):
            return id
        case let .stateChanges(_, id, _):
            return id
        case let .virtual(_, id, _):
            return id
        }
    }

    public init(timelineItem item: TimelineItem, version: Int) {
        if let event = item.asEvent() {
            if case let .msgLike(content: content) = event.content {
                self = .messages(messages: [TimelineGroup.Message(id: item.uniqueId().id, event: event, content: content)], id: item.uniqueId().id, version: version)
            } else {
                self = .stateChanges(events: [TimelineGroup.Event(id: item.uniqueId().id, event: event)], id: item.uniqueId().id, version: version)
            }
        } else {
            self = .virtual(item: item.asVirtual()!, id: item.uniqueId().id, version: version)
        }
    }

    public var count: Int {
        switch self {
        case let .messages(messages, _, _):
            return messages.count
        case let .stateChanges(events, _, _):
            return events.count
        case .virtual:
            return 1
        }
    }

    public var version: Int {
        switch self {
        case let .messages(_, _, version):
            return version
        case let .stateChanges(_, _, version):
            return version
        case let .virtual(_, _, version):
            return version
        }
    }

    public static func == (lhs: TimelineGroup, rhs: TimelineGroup) -> Bool {
        return lhs.id == rhs.id && lhs.version == rhs.version
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(version)
    }
}
