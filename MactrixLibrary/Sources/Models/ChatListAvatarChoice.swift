import Foundation

/// What a chat-list avatar draws (MATRIX-129).
///
/// `ChatListAvatar` switches on this value and holds no rule of its own, so
/// every choice is unit-tested here without a view.
public enum ChatListAvatarChoice: Equatable, Sendable {
    /// An image from an `mxc://` URL, clipped to a circle. The initials show
    /// while the image loads, and stay when it fails.
    case image(url: String, placeholder: ChatListInitials)
    /// The bubble cluster: one small circle per hero, in this order.
    case cluster(heroes: [ChatListHero])
    /// Colored initials in a circle.
    case initials(ChatListInitials)

    /// Fewest visible heroes for a group to draw the cluster. With one hero,
    /// a cluster would be one bubble and say less than the room's initial.
    public static let clusterMinimumHeroes = 2

    /// Picks the avatar for a chat-list row, in this order:
    ///
    /// 1. The room avatar, when the room has one.
    /// 2. A direct chat with exactly one visible hero who has an avatar: that
    ///    person's avatar.
    /// 3. A group (not direct) with two or more visible heroes: the cluster.
    /// 4. Otherwise colored initials. A direct chat takes a person's two
    ///    initials (from its one hero, else from the title and colored by room
    ///    ID); a group takes the room's one initial.
    ///
    /// - Parameters:
    ///   - roomId: the room ID. It colors room initials.
    ///   - title: the room's display name.
    ///   - avatarUrl: the room's own avatar URL.
    ///   - isDirect: the SDK's direct-chat flag.
    ///   - heroes: the visible heroes (`ChatListHero.visible`), in server order.
    public static func choose(
        roomId: String,
        title: String,
        avatarUrl: String?,
        isDirect: Bool,
        heroes: [ChatListHero]
    ) -> ChatListAvatarChoice {
        let initials = fallbackInitials(roomId: roomId, title: title, isDirect: isDirect, heroes: heroes)
        if let avatarUrl, !avatarUrl.isEmpty {
            return .image(url: avatarUrl, placeholder: initials)
        }
        if isDirect, heroes.count == 1, let heroAvatar = heroes.first?.avatarUrl, !heroAvatar.isEmpty {
            return .image(url: heroAvatar, placeholder: initials)
        }
        if !isDirect, heroes.count >= clusterMinimumHeroes {
            return .cluster(heroes: heroes)
        }
        return .initials(initials)
    }

    /// The initials step 4 draws, also the placeholder behind an image.
    static func fallbackInitials(
        roomId: String,
        title: String,
        isDirect: Bool,
        heroes: [ChatListHero]
    ) -> ChatListInitials {
        guard isDirect else {
            return .room(title: title, roomId: roomId)
        }
        if heroes.count == 1, let hero = heroes.first {
            return .person(displayName: hero.displayName, userId: hero.userId)
        }
        // A direct chat without one clear other person: the title is still a
        // person's name, but no user ID is known, so the room ID colors it.
        return ChatListInitials(
            text: ChatListInitials.personText(displayName: title, userId: ""),
            paletteIndex: AvatarColorHash.paletteIndex(forId: roomId)
        )
    }
}

/// The faces and overflow label of a bubble cluster (MATRIX-129).
public struct ChatListAvatarCluster: Equatable, Sendable {
    /// How many bubbles the cluster may draw. The view picks the mode from
    /// the avatar size (`ChatListToken.clusterFullModeMinimumSize`).
    public enum Mode: Equatable, Sendable {
        /// Up to three bubbles and no overflow label, for small avatars.
        case compact
        /// Up to five bubbles; the fifth can be a "+N" label.
        case full

        /// The most bubbles the mode draws, faces and label together.
        public var capacity: Int {
            switch self {
            case .compact: 3
            case .full: 5
            }
        }

        /// Only the full mode has room for a legible "+N".
        public var showsOverflow: Bool {
            self == .full
        }
    }

    /// The heroes that get a bubble, in server order.
    public var faces: [ChatListHero]
    /// The "+N" text for the bubble after the last face, or nil.
    public var overflowText: String?

    /// Lays out a cluster.
    ///
    /// In full mode, when the room has more other members than the mode has
    /// bubbles, the last bubble turns into "+N": four faces and "+N", where
    /// N is the members without a face. Otherwise every hero up to the
    /// capacity gets a face.
    ///
    /// - Parameters:
    ///   - heroes: the visible heroes, in server order (at most five).
    ///   - otherMemberCount: joined members other than the user
    ///     (`ChatListRowModel.countOtherMembers(joinedMembersCount:)`).
    ///   - mode: the cluster mode for the avatar size.
    public init(heroes: [ChatListHero], otherMemberCount: Int, mode: Mode) {
        if mode.showsOverflow, otherMemberCount > mode.capacity {
            let faces = Array(heroes.prefix(mode.capacity - 1))
            self.faces = faces
            overflowText = Self.overflowText(hiddenCount: otherMemberCount - faces.count)
        } else {
            faces = Array(heroes.prefix(mode.capacity))
            overflowText = nil
        }
    }

    /// The overflow label: "+N", or "99+" past 99, like the unread count.
    public static func overflowText(hiddenCount: Int) -> String {
        hiddenCount > 99 ? "99+" : "+\(hiddenCount)"
    }
}
