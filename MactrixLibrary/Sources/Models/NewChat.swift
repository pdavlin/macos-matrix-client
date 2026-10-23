import Foundation

/// Which flow the New Chat screen is in (MATRIX-75).
///
/// Mirrors Beeper's StartNewChatView: one draft pane with three modes rather
/// than three separate sheets.
public enum NewChatMode: Hashable, Sendable {
    /// A direct message with exactly one person.
    case direct
    /// A new group with one or more people and an optional name.
    case group
    /// Join an existing room by address or link.
    case join
}

/// A person the New Chat screen can show as a result row or a pill.
///
/// A value type rather than the SDK's `UserProfile` so the screen can be
/// snapshot-tested without the SDK.
public struct NewChatPerson: UserProfile, Hashable, Sendable {
    public let userId: String
    public let displayName: String?
    public let avatarUrl: String?

    public init(userId: String, displayName: String? = nil, avatarUrl: String? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }

    /// The name to show: the display name if set, else the user ID.
    public var label: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return userId
    }
}

/// Recognises a typed Matrix user ID (`@localpart:server`).
///
/// Synapse's user directory hides users the searcher shares no room with, so
/// a bridge bot such as `@slackbot:example.org` never comes back from a
/// search. The New Chat screen offers the typed ID as a row of its own when
/// this returns a value.
public enum MatrixUserID {
    /// Returns the trimmed user ID if `input` is one, else `nil`.
    ///
    /// The check is structural, not a full grammar: a non-empty localpart
    /// with no `:` or whitespace, and a server name that is a hostname, an
    /// IPv4 address, or a bracketed IPv6 address, with an optional port.
    /// The homeserver is the authority on whether the user exists.
    public static func parse(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 255, trimmed.hasPrefix("@") else { return nil }

        let body = trimmed.dropFirst()
        guard let colon = body.firstIndex(of: ":") else { return nil }

        let localpart = body[body.startIndex ..< colon]
        let serverName = body[body.index(after: colon)...]

        guard
            !localpart.isEmpty,
            !localpart.contains(where: { $0.isWhitespace || $0.isNewline }),
            isServerName(serverName)
        else { return nil }

        return trimmed
    }

    /// The server name part of a user ID, or `nil` if `userId` is not one.
    public static func serverName(of userId: String) -> String? {
        guard let id = parse(userId), let colon = id.firstIndex(of: ":") else { return nil }
        return String(id[id.index(after: colon)...])
    }

    static func isServerName(_ value: Substring) -> Bool {
        let hostname = /[A-Za-z0-9.\-]+(:[0-9]{1,5})?/
        let ipv6 = /\[[0-9A-Fa-f:.]+\](:[0-9]{1,5})?/
        return value.wholeMatch(of: hostname) != nil || value.wholeMatch(of: ipv6) != nil
    }
}

/// Builds the rows the New Chat screen lists under the To: field.
public enum NewChatResults {
    /// Assembles the result rows for a query.
    ///
    /// - Parameters:
    ///   - query: the text in the To: field.
    ///   - resolvedProfile: the profile fetched for the query, if the query
    ///     is a user ID and the lookup succeeded.
    ///   - searchResults: the user directory results, in server order.
    ///   - ownUserId: the signed-in user, never offered as a chat partner.
    ///   - selectedUserIds: people already shown as pills.
    /// - Returns: the exact user ID row first (resolved profile, else a
    ///   matching directory result, else the bare ID), then the directory
    ///   results, with duplicates, the own user, and selected people removed.
    public static func assemble(
        query: String,
        resolvedProfile: NewChatPerson?,
        searchResults: [NewChatPerson],
        ownUserId: String?,
        selectedUserIds: Set<String>
    ) -> [NewChatPerson] {
        var rows: [NewChatPerson] = []

        if let exactId = MatrixUserID.parse(query) {
            if let resolvedProfile, resolvedProfile.userId == exactId {
                rows.append(resolvedProfile)
            } else if let match = searchResults.first(where: { $0.userId == exactId }) {
                rows.append(match)
            } else {
                rows.append(NewChatPerson(userId: exactId))
            }
        }

        rows.append(contentsOf: searchResults)

        var seen = selectedUserIds
        if let ownUserId { seen.insert(ownUserId) }

        return rows.filter { seen.insert($0.userId).inserted }
    }
}

/// What the New Chat screen asks the app to start.
public enum NewChatStartRequest: Hashable, Sendable {
    /// A direct message with one person.
    case direct(userId: String)
    /// A new group room.
    case group(name: String?, userIds: [String], isEncrypted: Bool)

    /// The request for the current draft, or `nil` if the draft cannot start.
    ///
    /// A direct chat needs exactly one person. A group needs at least one;
    /// its name is optional and blank names become `nil`. Join mode never
    /// starts a chat.
    public static func make(
        mode: NewChatMode,
        selected: [NewChatPerson],
        groupName: String,
        isEncrypted: Bool
    ) -> NewChatStartRequest? {
        switch mode {
        case .direct:
            guard selected.count == 1, let person = selected.first else { return nil }
            return .direct(userId: person.userId)
        case .group:
            guard !selected.isEmpty else { return nil }
            let name = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
            return .group(
                name: name.isEmpty ? nil : name,
                userIds: selected.map(\.userId),
                isEncrypted: isEncrypted
            )
        case .join:
            return nil
        }
    }
}

/// The step the app takes for a start request.
public enum NewChatStartPlan: Hashable, Sendable {
    /// Open a room that already exists.
    case openRoom(roomId: String)
    /// Create an encrypted direct message room and invite one person.
    case createDirect(userId: String)
    /// Create a group room and invite everyone in it.
    case createGroup(name: String?, userIds: [String], isEncrypted: Bool)

    /// Decides the step for `request`.
    ///
    /// - Parameter existingDirectRoomId: the room the SDK reports as the DM
    ///   with the person, if any. Only a direct request reuses a room; a
    ///   group always creates a new one.
    public static func make(request: NewChatStartRequest, existingDirectRoomId: String?) -> NewChatStartPlan {
        switch request {
        case let .direct(userId):
            if let existingDirectRoomId { return .openRoom(roomId: existingDirectRoomId) }
            return .createDirect(userId: userId)
        case let .group(name, userIds, isEncrypted):
            return .createGroup(name: name, userIds: userIds, isEncrypted: isEncrypted)
        }
    }
}
