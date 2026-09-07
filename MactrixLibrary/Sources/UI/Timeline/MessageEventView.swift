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

    public var body: some View {
        // Profile icon and name
        Button(action: actions.focusUser) {
            HStack(spacing: 0) {
                HStack(spacing: 0) {
                    AvatarImage(userProfile: event, imageLoader: imageLoader)
                        .frame(width: DensityToken.profileAvatarSize, height: DensityToken.profileAvatarSize)
                        .clipShape(Circle())
                }.frame(width: DensityToken.leadingColumnWidth)

                Username(userProfile: event)
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

    @ViewBuilder
    var hoverActions: some View {
        HStack(spacing: 0) {
            HoverButton(icon: { Text("👍") }, tooltip: "React") {
                actions.toggleReaction(key: "👍")
            }
            HoverButton(icon: { Text("🎉") }, tooltip: "React") {
                actions.toggleReaction(key: "🎉")
            }
            HoverButton(icon: { Text("❤️") }, tooltip: "React") {
                actions.toggleReaction(key: "❤️")
            }
            Divider().frame(height: DensityToken.hoverActionsDividerHeight)
            HoverButton(icon: { Image(systemName: "face.smiling") }, tooltip: "React") {}

            if event.canBeRepliedTo {
                HoverButton(icon: { Image(systemName: "arrowshape.turn.up.left") }, tooltip: "Reply") {
                    actions.reply()
                }

                HoverButton(icon: { Image(systemName: "ellipsis.message") }, tooltip: "Reply in thread") {
                    actions.replyInThread()
                }
            }

            HoverButton(icon: { Image(systemName: "pin") }, tooltip: "Pin") {
                actions.pin()
            }
        }
        .padding(DensityToken.hoverActionsPadding)
        .background(
            RoundedRectangle(cornerRadius: BubbleToken.cornerRadius)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(Color(NSColor.separatorColor), lineWidth: BubbleToken.hoverBorderWidth)
                .shadow(color: .black.opacity(BubbleToken.hoverShadowOpacity), radius: BubbleToken.hoverShadowRadius)
        )
        .padding(.trailing, DensityToken.hoverActionsTrailingPadding)
        .padding(.top, DensityToken.hoverActionsTopOffset)
        .opacity(hoverText ? 1 : 0)
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
        .onHover { hover in
            hoverText = hover
        }
        .padding(.bottom, reactions.isEmpty ? 0 : DensityToken.reactionRowSpacing)
    }

    private var hasBottomContent: Bool {
        !reactions.isEmpty || !event.userReadReceipts.isEmpty
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
