import Foundation
import Models
import OSLog

/// The own reactions the Unanswered filter knows (MATRIX-224).
///
/// The SDK's latest event (`Room.latestEvent()`) has no event ID and no
/// reactions, and the SDK gives reactions only on timeline items. So a
/// room's main timeline, while it is open, records here whether the user
/// reacted to its newest message (`LiveTimeline.noteOwnReactionMark()`).
/// The mark names that message by sender and time
/// (`ChatListMessageKey`); `ChatListUnanswered` compares it to the latest
/// event. A reaction made on another device shows here only after the
/// chat opens on this Mac.
///
/// One store for the process, keyed by room ID: the sidebar and the open
/// timelines use different `SidebarRoom` objects for the same room. The
/// marks are kept in `UserDefaults`, room IDs and times only, so a chat
/// the user reacted to stays out of Unanswered after a relaunch.
@MainActor @Observable
public final class OwnReactionMarks {
    public static let shared = OwnReactionMarks()

    /// The most marks kept. A new mark drops the oldest.
    static let limit = 500

    /// The mark of each room with one.
    public private(set) var marks: [String: ChatListMessageKey]

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    /// - Parameters:
    ///   - defaults: where the marks are kept.
    ///   - key: the defaults key.
    init(defaults: UserDefaults = .standard, key: String = "chatListOwnReactionMarks") {
        self.defaults = defaults
        self.key = key
        marks = Self.read(defaults.data(forKey: key)) ?? [:]
    }

    private static func read(_ data: Data?) -> [String: ChatListMessageKey]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([String: ChatListMessageKey].self, from: data)
    }

    /// Sets or removes the mark of a room. Writes only on a change.
    ///
    /// - Parameters:
    ///   - mark: the room's newest message when the user reacted to it, or
    ///     nil.
    ///   - roomId: the room.
    public func record(_ mark: ChatListMessageKey?, roomId: String) {
        guard marks[roomId] != mark else { return }
        var next = marks
        next[roomId] = mark
        if next.count > Self.limit {
            let oldest = next.sorted { $0.value.timestamp < $1.value.timestamp }.prefix(next.count - Self.limit)
            for (roomId, _) in oldest {
                next[roomId] = nil
            }
        }
        marks = next
        save()
    }

    /// Drops every mark, for the sign-out.
    public func removeAll() {
        guard !marks.isEmpty else { return }
        marks = [:]
        defaults.removeObject(forKey: key)
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(marks)
            defaults.set(data, forKey: key)
        } catch {
            Logger.matrixClient.error("own reaction marks: save failed: \(error)")
        }
    }
}
