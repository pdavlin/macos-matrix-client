import Foundation
import MatrixRustSDK
import Models

// MARK: - Chat-list mapping (MATRIX-67)

// SDK → Models translation for the sidebar inbox. The wording rules live in
// `Models.ChatListLatestEvent.preview(isDirect:)`; this file only names which
// SDK case is which neutral kind. Content switches are exhaustive with no
// `default`, so a new SDK case breaks the build instead of silently showing
// no preview.

extension MatrixRustSDK.LatestEventValue {
    /// The room's latest event as the chat list describes it, or nil when the
    /// SDK has none.
    var chatListEvent: Models.ChatListLatestEvent? {
        switch self {
        case .none:
            return nil
        case let .remote(timestamp: timestamp, sender: sender, isOwn: isOwn, profile: profile, content: content):
            return content.chatListEvent(
                timestamp: timestamp,
                sender: ChatListSender(userId: sender, displayName: profile.readyDisplayName, isOwn: isOwn),
                hasSendFailure: false
            )
        case let .remoteInvite(timestamp: timestamp, inviter: inviter, inviterProfile: inviterProfile):
            return ChatListLatestEvent(
                timestamp: Self.date(timestamp),
                sender: ChatListSender(userId: inviter ?? "", displayName: inviterProfile.readyDisplayName, isOwn: false),
                content: .invite
            )
        case let .local(timestamp: timestamp, sender: sender, profile: profile, content: content, state: state):
            // A local echo is always the account's own event.
            return content.chatListEvent(
                timestamp: timestamp,
                sender: ChatListSender(userId: sender, displayName: profile.readyDisplayName, isOwn: true),
                hasSendFailure: state.isSendFailure
            )
        }
    }

    /// The SDK timestamp is milliseconds since the Unix epoch.
    static func date(_ timestamp: Timestamp) -> Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000)
    }
}

extension MatrixRustSDK.LatestEventValueLocalState {
    /// The send queue gave up on this local echo. The row shows a red error
    /// dot.
    var isSendFailure: Bool {
        switch self {
        case .cannotBeSent:
            return true
        case .isSending, .hasBeenSent:
            return false
        }
    }
}

extension MatrixRustSDK.ProfileDetails {
    /// The display name once the profile has loaded; nil while it is pending,
    /// unavailable, or failed, so the preview falls back to the localpart.
    var readyDisplayName: String? {
        guard case let .ready(displayName: displayName, displayNameAmbiguous: _, avatarUrl: _) = self else {
            return nil
        }
        return displayName
    }
}

extension MatrixRustSDK.TimelineItemContent {
    func chatListEvent(
        timestamp: Timestamp,
        sender: ChatListSender,
        hasSendFailure: Bool
    ) -> Models.ChatListLatestEvent {
        var sender = sender
        // A membership line names the member whose membership changed, which
        // is not always the event's sender (an invite, a kick).
        if case let .roomMembership(userId: userId, userDisplayName: userDisplayName, change: _, reason: _) = self {
            sender = ChatListSender(userId: userId, displayName: userDisplayName, isOwn: false)
        }
        return ChatListLatestEvent(
            timestamp: MatrixRustSDK.LatestEventValue.date(timestamp),
            sender: sender,
            content: chatListContent,
            hasSendFailure: hasSendFailure
        )
    }

    var chatListContent: Models.ChatListPreviewContent {
        switch self {
        case let .msgLike(content: content):
            return content.kind.chatListContent
        case let .roomMembership(userId: _, userDisplayName: _, change: change, reason: _):
            return .membership(Self.chatListMembershipChange(change))
        case .callInvite, .rtcNotification, .profileChange, .state, .failedToParseMessageLike, .failedToParseState:
            return .other
        }
    }

    private static func chatListMembershipChange(_ change: MatrixRustSDK.MembershipChange?) -> Models.ChatListMembershipChange {
        switch change {
        case .joined, .invitationAccepted:
            return .joined
        case .left:
            return .left
        case .invited:
            return .invited
        default:
            return .other
        }
    }
}

extension MatrixRustSDK.MsgLikeKind {
    var chatListContent: Models.ChatListPreviewContent {
        switch self {
        case let .message(content: content):
            return content.msgType.chatListContent
        case .sticker:
            return .sticker
        case let .poll(
            question: question,
            kind: _,
            maxSelections: _,
            answers: _,
            votes: _,
            endTime: _,
            hasBeenEdited: _
        ):
            return .poll(question: question)
        case .redacted:
            return .redacted
        case .unableToDecrypt:
            return .unableToDecrypt
        case .other:
            return .other
        case .liveLocation:
            return .location
        }
    }
}

extension MatrixRustSDK.MessageType {
    var chatListContent: Models.ChatListPreviewContent {
        switch self {
        case let .text(content: content):
            return .text(content.body)
        case let .notice(content: content):
            return .text(content.body)
        case let .emote(content: content):
            return .emote(content.body)
        case .image:
            return .image
        case .video:
            return .video
        case .audio:
            return .audio
        case let .file(content: content):
            return .file(name: content.filename)
        case .gallery:
            return .gallery
        case .location:
            return .location
        case let .other(msgtype: _, body: body):
            return .text(body)
        }
    }
}

extension Models.ChatListFilter {
    /// The SDK room-list filter for this chat-list filter.
    ///
    /// Unread, People, and Groups refine the inbox, so they also exclude low
    /// priority rooms. Every kind is OR-ed with `.space`: the Spaces section
    /// and the space-child rows look up joined spaces in the same entries list,
    /// and a filter that dropped them would turn joined spaces into "Join"
    /// rows. The chat list itself skips spaces.
    var roomListFilter: RoomListEntriesDynamicFilterKind {
        let chats: [RoomListEntriesDynamicFilterKind] = switch self {
        case .inbox:
            [.nonLowPriority]
        case .unread:
            [.nonLowPriority, .unread]
        case .people:
            [.nonLowPriority, .category(expect: .people)]
        case .groups:
            [.nonLowPriority, .category(expect: .group)]
        case .lowPriority:
            [.lowPriority]
        }
        return .any(filters: [.space, .all(filters: chats)])
    }
}

extension SidebarRoom {
    /// The chat-list row for this room. `now` decides the timestamp bucket.
    func chatListRow(now: Date = .now) -> Models.ChatListRowModel {
        let isDirect = roomInfo?.isDirect == true
        let preview = latestEvent?.preview(isDirect: isDirect)
        let unread = roomInfo.map { info in
            ChatListUnread(
                numUnreadMessages: info.numUnreadMessages,
                numUnreadNotifications: info.numUnreadNotifications,
                numUnreadMentions: info.numUnreadMentions,
                isMarkedUnread: info.isMarkedUnread,
                isMuted: info.isMuted
            )
        } ?? ChatListUnread()

        return ChatListRowModel(
            id: id,
            title: room.displayName() ?? (isDirect ? "Unknown user" : "Unknown room"),
            avatarUrl: room.avatarUrl(),
            isDirect: isDirect,
            preview: preview?.text,
            timestamp: latestEvent.map { ChatListTimestamp.text(for: $0.timestamp, now: now) },
            unread: unread,
            hasSendFailure: preview?.hasSendFailure ?? false,
            network: roomInfo.flatMap { ChatListNetwork.detect(heroUserIds: $0.heroes.lazy.map(\.userId)) }
        )
    }
}

extension MatrixRustSDK.RoomInfo {
    /// The user set the room's notification mode to mute. Display only.
    var isMuted: Bool {
        if case .mute = cachedUserDefinedNotificationMode {
            return true
        }
        return false
    }
}
