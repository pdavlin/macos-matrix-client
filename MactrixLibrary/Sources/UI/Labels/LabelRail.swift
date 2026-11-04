import Models
import SwiftUI
import Tokens

/// What the label rail asks the app to do (MATRIX-77). The rail owns no
/// state beyond the delete confirmation; every change goes through here.
public struct LabelRailActions {
    /// Select a rail item: nil is the Inbox.
    public var select: (String?) -> Void
    public var newLabel: () -> Void
    public var edit: (ChatLabel) -> Void
    public var toggleMute: (ChatLabel) -> Void
    public var toggleShowInInbox: (ChatLabel) -> Void
    /// Called after the user confirms.
    public var delete: (ChatLabel) -> Void

    public init(
        select: @escaping (String?) -> Void,
        newLabel: @escaping () -> Void,
        edit: @escaping (ChatLabel) -> Void,
        toggleMute: @escaping (ChatLabel) -> Void,
        toggleShowInInbox: @escaping (ChatLabel) -> Void,
        delete: @escaping (ChatLabel) -> Void
    ) {
        self.select = select
        self.newLabel = newLabel
        self.edit = edit
        self.toggleMute = toggleMute
        self.toggleShowInInbox = toggleShowInInbox
        self.delete = delete
    }

    /// Actions that do nothing, for previews and snapshots.
    public static var none: LabelRailActions {
        LabelRailActions(
            select: { _ in }, newLabel: {}, edit: { _ in }, toggleMute: { _ in }, toggleShowInInbox: { _ in }, delete: { _ in }
        )
    }
}

/// The narrow vertical rail at the leading edge of the sidebar: Beeper's
/// space bar, carrying labels (MATRIX-77).
///
/// The Inbox is the top item, then one item per label in document order,
/// then a "+" button. Selecting an item filters the chat list. ⌃1…⌃9 select
/// the first nine items; ⌘1…⌘9 stay reserved for room pinning (contract M2).
public struct LabelRail: View {
    let labels: [ChatLabel]
    let badges: [String: ChatLabelBadge]
    /// The selected label's ID; nil selects the Inbox.
    let selection: String?
    /// False when the labels document cannot be written (unreadable, or a
    /// newer schema): the menus and the "+" button turn off.
    let isEditable: Bool
    let actions: LabelRailActions

    @State private var pendingDelete: ChatLabel?

    public init(
        labels: [ChatLabel],
        badges: [String: ChatLabelBadge] = [:],
        selection: String?,
        isEditable: Bool = true,
        actions: LabelRailActions
    ) {
        self.labels = labels
        self.badges = badges
        self.selection = selection
        self.isEditable = isEditable
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: LabelToken.railItemSpacing) {
                    LabelRailItem(
                        title: "Inbox",
                        isSelected: selection == nil,
                        shortcutIndex: 0,
                        action: { actions.select(nil) },
                        icon: {
                            RoundedRectangle(cornerRadius: LabelToken.railIconCornerRadius, style: .continuous)
                                .fill(LabelToken.neutralFill)
                                .frame(width: LabelToken.railIconSize, height: LabelToken.railIconSize)
                                .overlay {
                                    Image(systemName: "tray.fill")
                                        .font(.system(size: LabelToken.railGlyphSize, weight: .semibold))
                                }
                        }
                    )

                    ForEach(Array(labels.enumerated()), id: \.element.id) { offset, label in
                        LabelRailItem(
                            label: label,
                            badge: badges[label.id] ?? .none,
                            isSelected: selection == label.id,
                            shortcutIndex: offset + 1
                        ) {
                            actions.select(label.id)
                        }
                        .contextMenu {
                            menu(for: label)
                        }
                    }
                }
                .padding(.vertical, LabelToken.railVerticalPadding)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.never)

            Button(action: actions.newLabel) {
                Image(systemName: "plus")
                    .font(.system(size: LabelToken.railGlyphSize, weight: .medium))
                    .frame(width: LabelToken.railItemSize, height: LabelToken.railItemSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(!isEditable)
            .help(isEditable ? "New Label…" : "Labels cannot be changed: Mactrix could not read the saved labels")
            .accessibilityLabel("New Label")
            .padding(.bottom, LabelToken.railVerticalPadding)
        }
        .frame(width: LabelToken.railWidth)
        .confirmationDialog(
            "Delete the label “\(pendingDelete?.name ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { label in
            Button("Delete Label", role: .destructive) {
                actions.delete(label)
            }
        } message: { _ in
            Text("The chats stay. Only the label is removed, on every device.")
        }
    }

    @ViewBuilder
    private func menu(for label: ChatLabel) -> some View {
        Group {
            Button("Edit Label…") { actions.edit(label) }
            Button(label.isMuted ? "Unmute Label" : "Mute Label") { actions.toggleMute(label) }
            Toggle(
                "Show in Inbox",
                isOn: Binding(get: { label.isShownInInbox }, set: { _ in actions.toggleShowInInbox(label) })
            )
            Divider()
            Button("Delete Label…", role: .destructive) { pendingDelete = label }
        }
        .disabled(!isEditable)
    }
}

/// One item of the label rail (MATRIX-77): a colored square with the item's
/// icon, a selected background, and an unread badge.
public struct LabelRailItem<Icon: View>: View {
    let title: String
    let badge: ChatLabelBadge
    let isSelected: Bool
    let isMuted: Bool
    /// The item's position in the rail; the first nine get ⌃1…⌃9.
    let shortcutIndex: Int?
    let action: () -> Void
    let icon: Icon

    public init(
        title: String,
        badge: ChatLabelBadge = .none,
        isSelected: Bool,
        isMuted: Bool = false,
        shortcutIndex: Int? = nil,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.badge = badge
        self.isSelected = isSelected
        self.isMuted = isMuted
        self.shortcutIndex = shortcutIndex
        self.action = action
        self.icon = icon()
    }

    private var shortcut: KeyEquivalent? {
        guard let shortcutIndex, (0 ..< 9).contains(shortcutIndex) else { return nil }
        return KeyEquivalent(Character(String(shortcutIndex + 1)))
    }

    private var helpText: String {
        var text = title
        if isMuted {
            text += " (muted)"
        }
        if let shortcutIndex, shortcut != nil {
            text += "  ⌃\(shortcutIndex + 1)"
        }
        return text
    }

    private var accessibilityText: String {
        var parts = [title]
        if isMuted {
            parts.append("muted")
        }
        if let badgeText = badge.accessibilityDescription {
            parts.append(badgeText)
        }
        return parts.joined(separator: ", ")
    }

    public var body: some View {
        Button(action: action) {
            icon
                .opacity(isMuted ? LabelToken.railMutedOpacity : 1)
                .overlay(alignment: .topTrailing) {
                    LabelBadgeView(badge: badge)
                        .fixedSize()
                        .offset(x: LabelToken.badgeOffset, y: -LabelToken.badgeOffset)
                }
                .overlay(alignment: .bottomTrailing) {
                    if isMuted {
                        Image(systemName: "bell.slash.fill")
                            .font(.system(size: LabelToken.railMutedGlyphSize, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(width: LabelToken.railMutedMarkSize, height: LabelToken.railMutedMarkSize)
                            .background(Circle().fill(.background))
                            .offset(x: LabelToken.badgeOffset, y: LabelToken.badgeOffset)
                    }
                }
                .frame(width: LabelToken.railItemSize, height: LabelToken.railItemSize)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: LabelToken.railItemCornerRadius, style: .continuous)
                            .fill(Color.primary.opacity(LabelToken.railSelectedOpacity))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: LabelToken.railItemCornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .modifier(OptionalControlShortcut(key: shortcut))
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

public extension LabelRailItem where Icon == LabelIcon {
    /// The item for a label.
    init(label: ChatLabel, badge: ChatLabelBadge, isSelected: Bool, shortcutIndex: Int?, action: @escaping () -> Void) {
        self.init(
            title: label.name,
            badge: badge,
            isSelected: isSelected,
            isMuted: label.isMuted,
            shortcutIndex: shortcutIndex,
            action: action,
            icon: { LabelIcon(label: label) }
        )
    }
}

/// ⌃-digit shortcut when the item has one.
private struct OptionalControlShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .control)
        } else {
            content
        }
    }
}

#Preview {
    LabelRail(
        labels: [
            ChatLabel(id: "w", name: "Work", colorIndex: 6, icon: "briefcase"),
            ChatLabel(id: "f", name: "Family", colorIndex: 0, isMuted: true),
        ],
        badges: ["w": .count(3)],
        selection: nil,
        actions: .none
    )
    .frame(height: 300)
}
