import Foundation

/// The bridge info of a bridged room (MATRIX-165): the `m.bridge` state event
/// that a mautrix bridge writes into each room it makes.
///
/// The app reads one field: `content.channel["fi.mau.receiver"]`, the login
/// ID of the bridge login that owns the room. The Slack bridge sets it on
/// direct chats, and it is the user's own ID in that workspace
/// (`docs/research/own-service-profile.md`, A2). Presentation only: the
/// value picks an avatar and nothing else.
public enum BridgeInfo {
    /// The event types, in the order of preference. Both carry the same
    /// content.
    public static let eventTypes = ["m.bridge", "uk.half-shot.bridge"]

    /// The room state is not a JSON array.
    public struct MalformedRoomState: Error, Equatable {
        public init() {}
    }

    /// The receiver of a room's bridge info.
    ///
    /// - Parameter data: The room's state, a JSON array of state events, as
    ///   `RoomStateReader` returns it.
    /// - Returns: The receiver of the first `m.bridge` event that has one,
    ///   else of the first `uk.half-shot.bridge` event that has one. Nil
    ///   when no event has a receiver. An empty receiver counts as absent.
    /// - Throws: `MalformedRoomState`.
    ///
    /// ```swift
    /// try BridgeInfo.receiver(roomState: state) // "T1C6G4L3C-U1CCDGWMD"
    /// ```
    public static func receiver(roomState data: Data) throws -> String? {
        guard case let .array(events)? = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw MalformedRoomState()
        }
        for eventType in eventTypes {
            for event in events {
                guard case let .object(fields) = event,
                      case .string(eventType)? = fields["type"],
                      case let .object(content)? = fields["content"],
                      case let .object(channel)? = content["channel"],
                      case let .string(receiver)? = channel["fi.mau.receiver"],
                      !receiver.isEmpty
                else { continue }
                return receiver
            }
        }
        return nil
    }
}

/// The user ID of the user's own bridge ghost in one workspace (MATRIX-165).
///
/// With double puppeting the own ghost is in no room, so no member list
/// shows it. The bridge keeps the ghost's global profile current, and its
/// user ID follows from two values of one direct chat: the receiver of the
/// bridge info, and the user ID of the other person's ghost. The rule never
/// reads a display name.
public enum OwnServiceGhost {
    /// Derives the own ghost's user ID.
    ///
    /// The receiver is `TEAM-USER` (the Slack bridge's login ID; the split is
    /// the one Slack-only rule here). A ghost's localpart is a prefix, then
    /// the lowercase team, `-`, and the lowercase user. The result is the
    /// peer's user ID with the user part replaced by the own user part: the
    /// prefix and the server name stay.
    ///
    /// Returns nil, so the caller draws no service image, when:
    /// - the receiver has no `-`, or the team or the user is empty or has a
    ///   character that is not an ASCII letter or digit;
    /// - the peer's ID is not `@localpart:server`;
    /// - the peer's localpart does not hold `<team>-` exactly once, or the
    ///   text after it is empty or is not only ASCII letters and digits (a
    ///   bot, another workspace's ghost, a username template with a suffix);
    /// - the result is the peer's ID (a chat with oneself);
    /// - the result is the account's own Matrix ID.
    ///
    /// - Parameters:
    ///   - receiver: `BridgeInfo.receiver(roomState:)` of a direct chat.
    ///   - peerUserId: The user ID of a ghost in the same direct chat.
    ///   - accountUserId: The signed-in account's Matrix ID.
    ///
    /// ```swift
    /// OwnServiceGhost.userId(
    ///     receiver: "T1C6G4L3C-U1CCDGWMD",
    ///     peerUserId: "@slack_t1c6g4l3c-u0456def:davlin.io",
    ///     accountUserId: "@patrick:davlin.io"
    /// ) // "@slack_t1c6g4l3c-u1ccdgwmd:davlin.io"
    /// ```
    public static func userId(receiver: String, peerUserId: String, accountUserId: String) -> String? {
        guard let dash = receiver.firstIndex(of: "-") else { return nil }
        let team = receiver[..<dash].lowercased()
        let user = receiver[receiver.index(after: dash)...].lowercased()
        guard isIdentifier(team), isIdentifier(user) else { return nil }

        guard peerUserId.hasPrefix("@"), let colon = peerUserId.firstIndex(of: ":") else { return nil }
        let localpart = String(peerUserId[peerUserId.index(after: peerUserId.startIndex) ..< colon])
        let server = peerUserId[peerUserId.index(after: colon)...]
        guard !server.isEmpty else { return nil }

        let parts = localpart.components(separatedBy: "\(team)-")
        guard parts.count == 2, isIdentifier(parts[1]) else { return nil }

        let ghost = "@\(parts[0])\(team)-\(user):\(server)"
        guard !isSameUser(ghost, peerUserId), !isSameUser(ghost, accountUserId) else { return nil }
        return ghost
    }

    /// The members of a direct chat that can be a peer ghost: not the
    /// account, not a service member, not a default bridge bot. The order
    /// stays, and a user ID shows once.
    ///
    /// - Parameters:
    ///   - userIds: The room's heroes.
    ///   - serviceMembers: The room's `io.element.functional_members`.
    ///   - accountUserId: The signed-in account's Matrix ID.
    public static func peers(
        among userIds: [String],
        serviceMembers: some Sequence<String>,
        accountUserId: String
    ) -> [String] {
        let services = Set(serviceMembers)
        var seen: Set<String> = []
        return userIds.filter { userId in
            !isSameUser(userId, accountUserId)
                && !services.contains(userId)
                && !ChatListHero.isBridgeBot(userId: userId)
                && seen.insert(userId).inserted
        }
    }

    private static func isIdentifier(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy { scalar in
            ("a" ... "z").contains(scalar) || ("0" ... "9").contains(scalar)
        }
    }

    private static func isSameUser(_ first: String, _ second: String) -> Bool {
        first.lowercased() == second.lowercased()
    }
}
