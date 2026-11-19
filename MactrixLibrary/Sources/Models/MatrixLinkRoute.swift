import Foundation

// MATRIX-203: a Matrix link in a message body opens in the app.
//
// The SDK parses the link (`parseMatrixEntityFrom(uri:)`, in Core) and
// answers the questions about the account: the alias's room, the
// membership, the DM, the event's thread. The rules between those answers
// live here, without the SDK, so they are unit-tested.

/// A room address in a Matrix link: a room ID or an alias.
public enum MatrixRoomAddress: Hashable, Sendable {
    /// A room ID, `!opaque:server` or `!opaque`.
    case id(String)
    /// A room alias, `#name:server`.
    case alias(String)
}

/// A Matrix link of a message body, as the SDK parsed it. Core makes it from
/// `MatrixRustSDK.MatrixEntity`.
public enum MatrixLink: Hashable, Sendable {
    /// A room, or one event in it.
    case room(MatrixRoomAddress, eventId: String?, via: [String])
    /// A user.
    case user(id: String)
}

/// Where a link click in a message body goes.
public enum BodyLinkRoute: Equatable, Sendable {
    /// A Matrix link: the app opens it (`MatrixLinkPlan`).
    case matrix(MatrixLink)
    /// An X or Bluesky post: the post peek popover (MATRIX-201).
    case postPeek
    /// The browser, as for any other link.
    case browser

    /// The one link router's rule: a Matrix link first, then a post peek
    /// link, then the browser. A click with a modifier key (⌘, ⌥, ⇧, ⌃)
    /// always goes to the browser.
    ///
    /// - Parameters:
    ///   - isPlainClick: a left click with no modifier key.
    ///   - matrixLink: the SDK's parse of the link, or nil when it is not a
    ///     Matrix link.
    ///   - isPostPeekLink: the link is an X or Bluesky post and the post peek
    ///     is on.
    public static func route(isPlainClick: Bool, matrixLink: MatrixLink?, isPostPeekLink: Bool) -> BodyLinkRoute {
        guard isPlainClick else { return .browser }
        if let matrixLink {
            return .matrix(matrixLink)
        }
        return isPostPeekLink ? .postPeek : .browser
    }
}

/// The event a Matrix link asks a window to show: the room's timeline
/// scrolls to it and flashes it. With a thread root, the thread panel opens
/// on that root and scrolls to the event.
public struct MatrixLinkEventFocus: Hashable, Sendable {
    public let roomId: String
    public let eventId: String
    /// The root of the event's thread, or nil for an event of the main
    /// timeline.
    public let threadRootId: String?

    public init(roomId: String, eventId: String, threadRootId: String? = nil) {
        self.roomId = roomId
        self.eventId = eventId
        self.threadRootId = threadRootId
    }
}

/// What the New Chat screen starts with when a link opens it.
public enum NewChatPrefill: Hashable, Sendable {
    /// The join field holds this address or link.
    case joinAddress(String)
    /// The To: field holds this person.
    case person(NewChatPerson)
}

/// What the account knows about a Matrix link, from the SDK.
public struct MatrixLinkFacts: Equatable, Sendable {
    /// The room ID of a room link: the ID itself, or the alias's room. Nil
    /// for a user link and for an alias that did not resolve.
    public var roomId: String?
    /// The account has joined `roomId`.
    public var isJoined: Bool
    /// The root of the linked event's thread, or nil when the event is in
    /// the main timeline or could not be loaded.
    public var threadRootId: String?
    /// The DM with the linked user, or nil.
    public var directRoomId: String?

    public init(roomId: String? = nil, isJoined: Bool = false, threadRootId: String? = nil, directRoomId: String? = nil) {
        self.roomId = roomId
        self.isJoined = isJoined
        self.threadRootId = threadRootId
        self.directRoomId = directRoomId
    }
}

/// What the app does with a Matrix link.
public enum MatrixLinkPlan: Equatable, Sendable {
    /// Open the chat, the same way a chat-list click does, and show the
    /// event if there is one.
    case open(ChatSelection, focus: MatrixLinkEventFocus?)
    /// Show the New Chat screen in this mode, prefilled.
    case newChat(NewChatMode, NewChatPrefill)

    /// Decides what a Matrix link opens.
    ///
    /// - A joined room opens. A room that is a member of a merged chat opens
    ///   the merged chat (MATRIX-141), as the chat list does.
    /// - An event link also shows the event. A thread reply opens the thread
    ///   panel on its root. A merged chat has no thread panel, so it shows
    ///   the thread's root.
    /// - A room the account has not joined, or an alias that did not
    ///   resolve, opens the New Chat join flow with the link (MATRIX-75).
    /// - A user opens the DM with them, or the New Chat flow with them in
    ///   the To: field.
    ///
    /// - Parameters:
    ///   - link: the parsed link.
    ///   - address: what the join field gets: the clicked link text.
    ///   - facts: the SDK's answers about the link.
    ///   - document: the account's merged chats.
    public static func make(
        link: MatrixLink,
        address: String,
        facts: MatrixLinkFacts,
        document: MergedChatDocument
    ) -> MatrixLinkPlan {
        switch link {
        case let .user(userId):
            if let directRoomId = facts.directRoomId {
                return .open(MergedChatSelection.selection(showing: directRoomId, document: document), focus: nil)
            }
            return .newChat(.direct, .person(NewChatPerson(userId: userId)))
        case let .room(_, eventId, _):
            guard let roomId = facts.roomId, facts.isJoined else {
                return .newChat(.join, .joinAddress(address))
            }
            let selection = MergedChatSelection.selection(showing: roomId, document: document)
            let focus = eventId.map { eventId in
                eventFocus(roomId: roomId, eventId: eventId, threadRootId: facts.threadRootId, selection: selection)
            }
            return .open(selection, focus: focus)
        }
    }

    private static func eventFocus(
        roomId: String,
        eventId: String,
        threadRootId: String?,
        selection: ChatSelection
    ) -> MatrixLinkEventFocus {
        guard let threadRootId, threadRootId != eventId else {
            return MatrixLinkEventFocus(roomId: roomId, eventId: eventId)
        }
        if selection.mergedChatId != nil {
            return MatrixLinkEventFocus(roomId: roomId, eventId: threadRootId)
        }
        return MatrixLinkEventFocus(roomId: roomId, eventId: eventId, threadRootId: threadRootId)
    }

    /// Whether a window can open `link` itself. A main window opens every
    /// link. A single-room window (MATRIX-116) opens only links to its own
    /// room, by room ID; for any other link the app brings a main window
    /// forward, as for a notification.
    public static func opens(_ link: MatrixLink, inWindowOf singleRoomId: String?) -> Bool {
        guard let singleRoomId else { return true }
        if case let .room(.id(roomId), _, _) = link {
            return roomId == singleRoomId
        }
        return false
    }
}
