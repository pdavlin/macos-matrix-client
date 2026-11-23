import Models
import SwiftUI
import Tokens

/// What the rows of the scheduled list do (MATRIX-212).
public struct ScheduledMessageActions {
    public var sendNow: (ScheduledMessageItem) -> Void
    public var edit: (ScheduledMessageItem) -> Void
    public var cancel: (ScheduledMessageItem) -> Void

    public init(
        sendNow: @escaping (ScheduledMessageItem) -> Void,
        edit: @escaping (ScheduledMessageItem) -> Void,
        cancel: @escaping (ScheduledMessageItem) -> Void
    ) {
        self.sendNow = sendNow
        self.edit = edit
        self.cancel = cancel
    }
}

/// The one-line strip above the composer of a chat with scheduled messages
/// (MATRIX-212): "2 scheduled" and the next time. A click opens the list in
/// a popover.
///
/// The background is opaque, as the thread-reply notice's is: the strip is
/// content, not navigation. The popover is the system's.
public struct ScheduledMessagesStrip: View {
    let items: [ScheduledMessageItem]
    let busyIds: Set<String>
    let isEditable: Bool
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let actions: ScheduledMessageActions

    @State private var isListShown = false

    /// - Parameters:
    ///   - items: the chat's scheduled messages, the earliest first.
    ///   - busyIds: the messages with an action in flight.
    ///   - isEditable: false turns every action off.
    ///   - now: the time the relative times count from.
    ///   - calendar: the calendar and time zone of the times.
    ///   - locale: the locale of the times.
    ///   - actions: the row actions.
    public init(
        items: [ScheduledMessageItem],
        busyIds: Set<String>,
        isEditable: Bool,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        actions: ScheduledMessageActions
    ) {
        self.items = items
        self.busyIds = busyIds
        self.isEditable = isEditable
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.actions = actions
    }

    public var body: some View {
        Button {
            isListShown.toggle()
        } label: {
            label
        }
        .buttonStyle(.plain)
        .help("Show the scheduled messages")
        .popover(isPresented: $isListShown, arrowEdge: .top) {
            ScheduledMessagesList(
                items: items,
                busyIds: busyIds,
                isEditable: isEditable,
                now: now,
                calendar: calendar,
                locale: locale,
                actions: closingActions
            )
        }
    }

    private var label: some View {
        HStack(spacing: DensityToken.sendFailureSpacing) {
            Image(systemName: "clock")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(ScheduledMessageStripText.title(count: items.count))
                .lineLimit(1)
            if let next = items.first {
                Text("Next: \(InboxTimeText.when(next.message.sendAt, now: now, calendar: calendar, locale: locale))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DensityToken.sendFailureSpacing)
            Image(systemName: "chevron.up")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .font(.footnote)
        .padding(.horizontal, DensityToken.rowHorizontalPadding)
        .padding(.vertical, DensityToken.rowVerticalPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: DensityToken.threadReplyNoticeCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: DensityToken.threadReplyNoticeCornerRadius)
                .strokeBorder(.separator)
        }
        .contentShape(.rect)
    }

    /// Edit opens a sheet, so the popover closes first.
    private var closingActions: ScheduledMessageActions {
        ScheduledMessageActions(
            sendNow: actions.sendNow,
            edit: { item in
                isListShown = false
                actions.edit(item)
            },
            cancel: actions.cancel
        )
    }
}

/// The list of a chat's scheduled messages (MATRIX-212): each message with
/// its time and text, and Send Now, Edit, and Cancel. A message from
/// another device shows "Scheduled message" and cannot be edited, because
/// this Mac does not have its text.
public struct ScheduledMessagesList: View {
    let items: [ScheduledMessageItem]
    let busyIds: Set<String>
    let isEditable: Bool
    let now: Date
    let calendar: Calendar
    let locale: Locale
    let actions: ScheduledMessageActions

    static var width: CGFloat { 340 }
    static var maxHeight: CGFloat { 420 }

    public init(
        items: [ScheduledMessageItem],
        busyIds: Set<String>,
        isEditable: Bool,
        now: Date = .now,
        calendar: Calendar = .current,
        locale: Locale = .current,
        actions: ScheduledMessageActions
    ) {
        self.items = items
        self.busyIds = busyIds
        self.isEditable = isEditable
        self.now = now
        self.calendar = calendar
        self.locale = locale
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(width: Self.width)
        .frame(maxHeight: Self.maxHeight)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ item: ScheduledMessageItem) -> some View {
        let isBusy = busyIds.contains(item.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(TimeInputText.full(item.message.sendAt, now: now, calendar: calendar, locale: locale))
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(relativeTime(item.message.sendAt))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .font(.callout)
            Group {
                if let text = item.text {
                    Text(text)
                } else {
                    Text(ScheduledMessageStripText.unknownText)
                        .italic()
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                Button("Send Now") { actions.sendNow(item) }
                Button("Edit") { actions.edit(item) }
                    .disabled(item.text == nil)
                Button("Cancel") { actions.cancel(item) }
            }
            .linkButtonStyle()
            .font(.callout)
            .disabled(isBusy || !isEditable)
        }
        .padding(12)
        .accessibilityElement(children: .contain)
    }

    /// "in 2 hours", or "sending" once the time has come.
    private func relativeTime(_ date: Date) -> String {
        date <= now ? "sending" : TimeInputText.relative(date, now: now, calendar: calendar, locale: locale)
    }
}

#Preview {
    let now = Date.now
    let items = [
        ScheduledMessageItem(
            message: ScheduledMessage(delayId: "a", roomId: "!a", sendAt: now.addingTimeInterval(3600)),
            text: "Lunch at noon?"
        ),
        ScheduledMessageItem(
            message: ScheduledMessage(delayId: "b", roomId: "!a", sendAt: now.addingTimeInterval(86400)),
            text: nil
        ),
    ]
    let actions = ScheduledMessageActions(sendNow: { _ in }, edit: { _ in }, cancel: { _ in })
    VStack {
        ScheduledMessagesStrip(items: items, busyIds: [], isEditable: true, now: now, actions: actions)
        ScheduledMessagesList(items: items, busyIds: [], isEditable: true, now: now, actions: actions)
    }
    .padding()
    .frame(width: 420)
}
