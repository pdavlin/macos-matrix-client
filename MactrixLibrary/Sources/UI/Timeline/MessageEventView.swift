import Models
import SwiftUI
import Tokens

@MainActor
public protocol MessageEventActions {
    func toggleReaction(key: String)
    func reply()
    func replyInThread()
    func pin()
    func focusUser()

    /// The facts the action model reads for this message (MATRIX-108). Nil
    /// means the conformer has no message menu: the row then draws no
    /// right-click menu.
    var actionSubject: MessageActionSubject? { get }

    /// The quick reactions of the React submenu: the account's top recent
    /// emoji (MATRIX-111, D-3).
    var quickReactionKeys: [String] { get }

    /// Runs one action from the right-click menu.
    func perform(_ action: MessageAction)

    /// Whether the timeline has a message selection (MATRIX-113). The
    /// right-click menu offers Copy Messages only then.
    var hasMessageSelection: Bool { get }

    /// Handles a click in the message's selection gutter (the timestamp
    /// column), or nil when the conformer has no message selection. With
    /// nil, the gutter takes no clicks.
    var messageSelectionHandler: (@MainActor (MessageSelectionGesture) -> Void)? { get }
}

/// Defaults that keep conformers from before MATRIX-108 (the iOS rows, the
/// timeline gate's shim, the mocks) working without a change.
public extension MessageEventActions {
    var actionSubject: MessageActionSubject? {
        nil
    }

    var quickReactionKeys: [String] {
        MessageActionModel.defaultQuickReactionKeys
    }

    func perform(_ action: MessageAction) {
        switch action {
        case .reply: reply()
        case .replyInThread: replyInThread()
        case let .toggleReaction(key): toggleReaction(key: key)
        case .pin: pin()
        case .openReactionPicker, .edit, .forward, .copyText, .copyLink, .unpin, .quickLook, .playInline, .saveToDownloads, .redact,
             .copyMessages, .openOriginalLink, .copyOriginalLink, .bookmark, .removeBookmark, .showEditHistory:
            break
        }
    }

    var hasMessageSelection: Bool {
        false
    }

    var messageSelectionHandler: (@MainActor (MessageSelectionGesture) -> Void)? {
        nil
    }
}

struct MessageTimestampView: View {
    let date: Date
    let hover: Bool

    @Environment(\.timelineTypography) private var typography
    /// MATRIX-208: a bookmarked message shows a small mark before its time.
    @Environment(\.timelineRowIsBookmarked) private var isBookmarked

    var timeFormat: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }

    var body: some View {
        HStack {
            Text(timeFormat.string(from: date))
                .foregroundStyle(.gray)
                .font(.system(size: typography.footnote))
                // An overlay, so the mark never changes the column or the
                // row height (MATRIX-63).
                .overlay(alignment: .leading) {
                    if isBookmarked {
                        // A zero-width frame on the time's leading edge,
                        // with the mark on its trailing side: the mark ends
                        // just before the time.
                        BookmarkMark(size: typography.footnote)
                            .fixedSize()
                            .frame(width: 0, alignment: .trailing)
                            .offset(x: -BookmarkMark.spacing)
                    }
                }
                .padding(.trailing, DensityToken.timestampTrailingPadding)
                .padding(.top, DensityToken.timestampTopPadding)
        }
        .frame(width: DensityToken.timestampColumnWidth)
        // .opacity(hover ? 1 : 0)
    }
}

/// The mark of a bookmarked message (MATRIX-208): a filled bookmark in the
/// accent color, a little smaller than the time beside it.
struct BookmarkMark: View {
    /// The point size of the time text the mark sits beside.
    let size: CGFloat

    /// The gap between the mark and the time.
    static let spacing: CGFloat = 2

    var body: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: size * 0.8))
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel("Bookmarked")
    }
}

struct MessageMainBody<MessageView: View, EventTimelineItem: Models.EventTimelineItem>: View {
    let event: EventTimelineItem
    let message: MessageView
    let hover: Bool
    let focused: Bool
    /// Handles a click in the selection gutter, or nil for no gutter
    /// (MATRIX-113).
    var select: (@MainActor (MessageSelectionGesture) -> Void)?

    /// Whether the row is the root of the thread panel it is in
    /// (MATRIX-183).
    @Environment(\.timelineRowIsThreadRoot) private var isThreadRoot

    var body: some View {
        // Main body
        HStack(alignment: .top, spacing: 0) {
            MessageTimestampView(date: event.date, hover: hover)
            message
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DensityToken.rowVerticalPadding)
        // An overlay takes the size of the view under it and never sizes it,
        // so the gutter cannot change the row height (MATRIX-63).
        .overlay(alignment: .leading) {
            if let select {
                MessageSelectionGutter(select: select)
            }
        }
        // MATRIX-183: the accent bar of the panel's root, in the leading
        // column. An overlay, so it cannot change the row height.
        .overlay(alignment: .leading) {
            if isThreadRoot {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: ThreadToken.rootBarWidth)
                    .allowsHitTesting(false)
            }
        }
        .background(
            ZStack {
                // MATRIX-183: the permanent band of the panel's root, under
                // the hover and focus background. Same layer, so it stays out
                // of the row height.
                if isThreadRoot {
                    RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                        .fill(Color.accentColor.opacity(ThreadToken.rootBandOpacity))
                }
                RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                    .fill(
                        focused
                            ? Color.accentColor.opacity(AccentToken.focusBackgroundOpacity)
                            : Color.gray.opacity(AccentToken.hoverBackgroundOpacity)
                    )
                    .opacity(hover || focused ? AccentToken.activeBackgroundOpacity : AccentToken.inactiveBackgroundOpacity)
            }
        )
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
    }
}

public struct MessageEventProfileView<EventTimelineItem: Models.EventTimelineItem>: View {
    let event: EventTimelineItem
    let actions: MessageEventActions
    let imageLoader: ImageLoader?

    /// The account's global profile avatar (MATRIX-163). Only an own message
    /// without a room member avatar draws it.
    @Environment(\.ownAccountAvatarUrl) private var ownAccountAvatarUrl

    /// The user's profile image on the service of this row's room
    /// (MATRIX-165). Only an own message draws it, before the member avatar.
    @Environment(\.ownServiceAvatarUrl) private var ownServiceAvatarUrl

    public init(event: EventTimelineItem, actions: MessageEventActions, imageLoader: ImageLoader?) {
        self.event = event
        self.actions = actions
        self.imageLoader = imageLoader
    }

    var avatarUrl: String? {
        MessageAvatarRule.avatarUrl(
            serviceAvatarUrl: ownServiceAvatarUrl,
            memberAvatarUrl: event.avatarUrl,
            accountAvatarUrl: ownAccountAvatarUrl,
            isOwn: event.isOwn
        )
    }

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    /// The sender's palette color (MATRIX-68). Own messages take no slot and
    /// draw in the default text color.
    var nameColor: Color {
        guard !event.isOwn else { return .primary }
        return SenderColorToken.color(atSlot: SenderColorHash.paletteIndex(forSenderId: event.sender))
    }

    public var body: some View {
        // Profile icon and name
        Button(action: actions.focusUser) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    AvatarImage(avatarUrl: avatarUrl, imageLoader: imageLoader) {
                        UserAvatarPlaceholder(userProfile: event)
                    }
                    .frame(width: DensityToken.profileAvatarSize, height: DensityToken.profileAvatarSize)
                    .clipShape(Circle())
                }.frame(width: DensityToken.leadingColumnWidth)

                Username(userProfile: event, color: nameColor)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

public struct MessageEventBodyView<
    MessageView: View,
    EventTimelineItem: Models.EventTimelineItem,
    Reaction: Models.Reaction,
    RoomMember: Models.RoomMember
>: View {
    let event: EventTimelineItem
    let focused: Bool
    let reactions: [Reaction]
    let message: MessageView
    let actions: MessageEventActions
    let imageLoader: ImageLoader?
    let ownUserId: String
    let roomMembers: [RoomMember]

    /// D-3: receipts render in direct rooms only. The timeline container sets
    /// this from the room's direct flag.
    @Environment(\.timelineShowsReadReceipts) private var showsReadReceipts

    /// Whether the timeline's hover bar shows for this row (MATRIX-145). The
    /// timeline container sets it; the row draws its hover background from
    /// it.
    @Environment(\.timelineRowIsHovered) private var isHovered

    public init(
        event: EventTimelineItem,
        focused: Bool,
        reactions: [Reaction],
        actions: MessageEventActions,
        ownUserID: String,
        imageLoader: ImageLoader?,
        roomMembers: [RoomMember],
        @ViewBuilder message: () -> MessageView
    ) {
        self.event = event
        self.focused = focused
        self.reactions = reactions
        self.actions = actions
        self.ownUserId = ownUserID
        self.imageLoader = imageLoader
        self.roomMembers = roomMembers
        self.message = message()
    }

    var name: String {
        if case let .ready(displayName, _, _) = event.senderProfileDetails, let displayName = displayName {
            return displayName
        }
        return event.sender
    }

    func reactionIsActive(_ reaction: Reaction) -> Bool {
        return reaction.senders.contains(where: { $0.senderId == ownUserId })
    }

    public var body: some View {
        VStack(spacing: 0) {
            MessageMainBody(
                event: event,
                message: message,
                hover: isHovered,
                focused: focused,
                select: actions.messageSelectionHandler
            )

            // Always present to keep view tree stable (avoids NSHostingView layout loop)
            HStack {
                Spacer().frame(width: DensityToken.leadingColumnWidth)
                ForEach(reactions) { reaction in
                    MessageReactionView(
                        reaction: reaction,
                        active: Binding(
                            get: { reactionIsActive(reaction) },
                            set: { if $0 != reactionIsActive(reaction) { actions.toggleReaction(key: reaction.key) } }
                        ),
                        imageLoader: imageLoader,
                        ownUserId: ownUserId,
                        // MATRIX-166, MATRIX-259: names from the member
                        // list the row already has, in memory. The chip
                        // asks for each sender: no server request.
                        displayName: { userId in roomMembers.first { $0.userId == userId }?.displayName }
                    )
                }
                Spacer()
                if showsReadReceipts, !event.userReadReceipts.isEmpty {
                    ReadReciptsView(receipts: event.userReadReceipts, imageLoader: imageLoader, roomMembers: roomMembers)
                        .padding(.horizontal, DensityToken.rowHorizontalPadding)
                }
            }
            .padding(.top, hasBottomContent ? DensityToken.reactionRowSpacing : 0)
        }
        // The hover action bar is not part of the row. The Mac timeline draws
        // one bar above all rows (MATRIX-145), so the row above cannot cover
        // it.
        .modifier(MessageRowContextMenu(actions: actions))
        .padding(.bottom, reactions.isEmpty ? 0 : DensityToken.reactionRowSpacing)
    }

    private var hasBottomContent: Bool {
        !reactions.isEmpty || !event.userReadReceipts.isEmpty
    }
}

/// The right-click menu of a message row (MATRIX-108). It holds the row's
/// actions. Media actions live in the menu over the media view, which has the
/// state they need. A conformer without a subject gets no menu, so the iOS
/// rows keep their own.
struct MessageRowContextMenu: ViewModifier {
    let actions: MessageEventActions

    func body(content: Content) -> some View {
        if let subject = actions.actionSubject {
            content.contextMenu {
                MessageActionMenu(
                    items: MessageActionModel.items(
                        for: subject,
                        on: .contextMenu,
                        quickReactionKeys: actions.quickReactionKeys,
                        hasMessageSelection: actions.hasMessageSelection
                    )
                    .filter { !$0.action.isMediaAction },
                    perform: actions.perform
                )
            }
        } else {
            content
        }
    }
}

public extension EnvironmentValues {
    /// Whether the timeline's hover action bar shows for this message row
    /// (MATRIX-145). The row draws its hover background from it.
    ///
    /// The Mac timeline controller tracks the pointer and sets it on the one
    /// row its floating bar shows for, so the background and the bar always
    /// mark the same row, also while the pointer is over the bar where it
    /// covers a neighbor row. It is a background only: it never changes a
    /// row's height. Rows outside the Mac timeline keep the default, false.
    @Entry var timelineRowIsHovered: Bool = false

    /// Whether the message row is the root of the thread panel it is in
    /// (MATRIX-183). The row draws a permanent accent band and a leading
    /// accent bar. Both are a background and an overlay: they never change
    /// the row's height. Rows outside the thread panel keep the default,
    /// false.
    @Entry var timelineRowIsThreadRoot: Bool = false

    /// Whether the account bookmarked the message of this row (MATRIX-208).
    /// The timestamp draws a small bookmark mark before the time, as an
    /// overlay that never changes the row's height. Rows outside the Mac
    /// timeline keep the default, false.
    @Entry var timelineRowIsBookmarked: Bool = false

    /// The signed-in account's global profile avatar, an `mxc://` URL
    /// (MATRIX-163). The timeline container sets it from the client's one
    /// observable value. A message profile row draws it for an own message
    /// whose room member profile has no avatar; see `MessageAvatarRule`. The
    /// default, nil, keeps the member avatar or the initials.
    @Entry var ownAccountAvatarUrl: String?

    /// The avatar of the user's own bridge ghost in the workspace of the
    /// row's room, an `mxc://` URL (MATRIX-165). The timeline container sets
    /// it for each row from the client's observable store, by the row's
    /// room, so a merged chat draws each member room's own image. A message
    /// profile row draws it for an own message, first; see
    /// `MessageAvatarRule`. The default, nil, keeps the MATRIX-163 order.
    @Entry var ownServiceAvatarUrl: String?
}

public struct MockMessageEventActions: MessageEventActions {
    public func toggleReaction(key _: String) {}
    public func reply() {}
    public func replyInThread() {}
    public func pin() {}
    public func focusUser() {}
}

#Preview {
    VStack(spacing: 0) {
        MessageEventProfileView(event: MockEventTimelineItem(), actions: MockMessageEventActions(), imageLoader: nil)

        MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction](),
            actions: MockMessageEventActions(),
            ownUserID: "user@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember()]
        ) {
            Text("This is the body of the message")
        }

        MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction()],
            actions: MockMessageEventActions(),
            ownUserID: "user@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember()]
        ) {
            Text("This is another message from the same sender, this message is long enough that it will wrap to the next line".formatAsMarkdown)
        }

        MessageEventBodyView(
            event: MockEventTimelineItem(),
            focused: false,
            reactions: [MockReaction()],
            actions: MockMessageEventActions(),
            ownUserID: "user@example.com",
            imageLoader: nil,
            roomMembers: [MockRoomMember()]
        ) {
            Text("Yet another message")
        }
    }
}
