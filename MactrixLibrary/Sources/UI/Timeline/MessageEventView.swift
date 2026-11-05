import Models
import SwiftUI
import Tokens

struct HoverButton<Icon: View>: View {
    @State private var hovering = false

    @ViewBuilder
    let icon: () -> Icon
    let tooltip: LocalizedStringKey
    let action: () -> Void

    let size: CGFloat = DensityToken.hoverActionButtonSize

    var body: some View {
        Button(action: action) {
            icon()
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .foregroundStyle(hovering ? Color.accentColor : .primary)
        .background(
            RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                .fill(Color.accentColor.quaternary)
                .frame(width: size, height: size)
                .opacity(hovering ? 1 : 0)
        )
        .frame(width: size, height: size)
        .padding(DensityToken.hoverActionButtonPadding)
        .onHover { hover in
            hovering = hover
        }
    }
}

@MainActor
public protocol MessageEventActions {
    func toggleReaction(key: String)
    func reply()
    func replyInThread()
    func pin()
    func focusUser()

    /// The facts the action model reads for this message (MATRIX-108). Nil
    /// means the conformer has no message menu: the row then draws no
    /// right-click menu, and the hover row falls back to its pre-M2 buttons.
    var actionSubject: MessageActionSubject? { get }

    /// The quick reactions of the hover row and the React submenu: the
    /// account's top recent emoji (MATRIX-111, D-3).
    var quickReactionKeys: [String] { get }

    /// Runs one action from the hover row or the right-click menu.
    func perform(_ action: MessageAction)
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
        case .openReactionPicker, .edit, .copyText, .copyLink, .unpin, .quickLook, .playInline, .saveToDownloads, .redact: break
        }
    }
}

extension MessageActionSubject {
    /// The subject for a conformer without one. It gives the pre-M2 hover row
    /// (quick reactions, picker, reply and thread when repliable, pin). The
    /// placeholder event ID only marks Pin as available, as it always was.
    static func hoverFallback(for event: some Models.EventTimelineItem) -> Self {
        MessageActionSubject(
            content: .other,
            isOwn: event.isOwn,
            eventId: "",
            canBeRepliedTo: event.canBeRepliedTo,
            isPinned: false,
            copyableText: nil
        )
    }
}

struct MessageTimestampView: View {
    let date: Date
    let hover: Bool

    @Environment(\.timelineTypography) private var typography

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
                .padding(.trailing, DensityToken.timestampTrailingPadding)
                .padding(.top, DensityToken.timestampTopPadding)
        }
        .frame(width: DensityToken.timestampColumnWidth)
        // .opacity(hover ? 1 : 0)
    }
}

struct MessageMainBody<MessageView: View, EventTimelineItem: Models.EventTimelineItem>: View {
    let event: EventTimelineItem
    let message: MessageView
    let hover: Bool
    let focused: Bool

    var body: some View {
        // Main body
        HStack(alignment: .top, spacing: 0) {
            MessageTimestampView(date: event.date, hover: hover)
            message
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DensityToken.rowVerticalPadding)
        .background(
            RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                .fill(
                    focused
                        ? Color.accentColor.opacity(AccentToken.focusBackgroundOpacity)
                        : Color.gray.opacity(AccentToken.hoverBackgroundOpacity)
                )
                .opacity(hover || focused ? AccentToken.activeBackgroundOpacity : AccentToken.inactiveBackgroundOpacity)
        )
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
    }
}

public struct MessageEventProfileView<EventTimelineItem: Models.EventTimelineItem>: View {
    let event: EventTimelineItem
    let actions: MessageEventActions
    let imageLoader: ImageLoader?

    public init(event: EventTimelineItem, actions: MessageEventActions, imageLoader: ImageLoader?) {
        self.event = event
        self.actions = actions
        self.imageLoader = imageLoader
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
                    AvatarImage(userProfile: event, imageLoader: imageLoader)
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

    @State private var hoverText: Bool = false

    /// The hover row's actions, from the shared action model (MATRIX-108).
    var hoverItems: [MessageActionItem] {
        let subject = actions.actionSubject ?? .hoverFallback(for: event)
        return MessageActionModel.items(for: subject, on: .hoverRow, quickReactionKeys: actions.quickReactionKeys)
    }

    func hoverButton(for item: MessageActionItem) -> some View {
        HoverButton(
            icon: {
                if let systemImage = MessageActionPresentation.systemImage(of: item.action) {
                    Image(systemName: systemImage)
                } else {
                    Text(MessageActionPresentation.title(of: item.action))
                }
            },
            tooltip: MessageActionPresentation.hoverTooltip(of: item.action),
            action: { actions.perform(item.action) }
        )
    }

    @ViewBuilder
    var hoverActions: some View {
        let items = hoverItems
        let reactions = items.filter(\.action.isQuickReaction)
        let others = items.filter { !$0.action.isQuickReaction }

        HStack(spacing: 0) {
            ForEach(reactions) { item in
                hoverButton(for: item)
            }
            if !reactions.isEmpty, !others.isEmpty {
                Divider().frame(height: DensityToken.hoverActionsDividerHeight)
            }
            ForEach(others) { item in
                hoverButton(for: item)
            }
        }
        // The row height must not depend on which buttons show (MATRIX-63):
        // the bar keeps one button's height even when it has no buttons.
        .frame(minHeight: DensityToken.hoverActionButtonSize + 2 * DensityToken.hoverActionButtonPadding)
        .padding(DensityToken.hoverActionsPadding)
        .background(
            RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                .fill(Color(PlatformColor.controlBackgroundColor))
                .stroke(Color(PlatformColor.separatorColor), lineWidth: BubbleToken.hoverBorderWidth)
                .shadow(color: .black.opacity(BubbleToken.hoverShadowOpacity), radius: BubbleToken.hoverShadowRadius)
        )
        .padding(.trailing, DensityToken.hoverActionsTrailingPadding)
        .padding(.top, DensityToken.hoverActionsTopOffset)
        .opacity(hoverText && !items.isEmpty ? 1 : 0)
    }

    func reactionIsActive(_ reaction: Reaction) -> Bool {
        return reaction.senders.contains(where: { $0.senderId == ownUserId })
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                MessageMainBody(
                    event: event,
                    message: message,
                    hover: hoverText,
                    focused: focused
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
                            )
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

            hoverActions
        }
        .modifier(MessageRowContextMenu(actions: actions))
        .onHover { hover in
            hoverText = hover
        }
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
                    items: MessageActionModel.items(for: subject, on: .contextMenu, quickReactionKeys: actions.quickReactionKeys)
                        .filter { !$0.action.isMediaAction },
                    perform: actions.perform
                )
            }
        } else {
            content
        }
    }
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
