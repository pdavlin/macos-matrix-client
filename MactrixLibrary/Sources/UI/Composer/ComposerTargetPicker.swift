import Models
import SwiftUI
import Tokens

/// One member room in the merged chat's target picker (MATRIX-143).
public struct ComposerTargetOption: Identifiable, Hashable, Sendable {
    /// The member room ID.
    public var id: String
    /// The room or account name, for example "DevObsessed".
    public var name: String
    /// The room's bridged network, if detected (`ChatListNetwork.detect`).
    public var network: ChatListNetwork?

    public init(id: String, name: String, network: ChatListNetwork? = nil) {
        self.id = id
        self.name = name
        self.network = network
    }
}

/// The chip that shows which member room a merged chat's composer sends to
/// (MATRIX-143, M2.5-4): "To: Slack • DevObsessed", the reason as a hint
/// ("Last active", "Default", "Chosen"), and a menu to pick another member
/// room.
///
/// The view only draws the chip and its menu and reports a choice. The
/// composer owns the target: it resolves it with `MergedSendTarget.resolve`
/// and stores the manual pick that `onSelect` reports. While the composer
/// replies or edits (`.reply`, `.edit`), the message must go to the event's
/// room, so the chip shows that room with no menu and no chevron.
///
/// The chip has a fixed height (`ComposerTargetToken.chipHeight`).
public struct ComposerTargetPicker: View {
    let options: [ComposerTargetOption]
    let selectedRoomId: String
    let reason: MergedSendTarget.Reason
    let onSelect: (String?) -> Void

    /// - Parameters:
    ///   - options: The member rooms, in member order.
    ///   - selectedRoomId: The current target's room ID
    ///     (`MergedSendTarget.roomId`).
    ///   - reason: Why the composer chose the room (`MergedSendTarget.reason`).
    ///   - onSelect: Called with the room ID the user picked, or with nil
    ///     when the user goes back to the automatic choice.
    public init(
        options: [ComposerTargetOption],
        selectedRoomId: String,
        reason: MergedSendTarget.Reason,
        onSelect: @escaping (String?) -> Void
    ) {
        self.options = options
        self.selectedRoomId = selectedRoomId
        self.reason = reason
        self.onSelect = onSelect
    }

    private var selected: ComposerTargetOption {
        options.first { $0.id == selectedRoomId } ?? ComposerTargetOption(id: selectedRoomId, name: selectedRoomId)
    }

    /// A reply or an edit pins the target to the event's room.
    private var isLocked: Bool {
        reason == .reply || reason == .edit
    }

    private var selection: Binding<String> {
        Binding(
            get: { selectedRoomId },
            set: { onSelect($0) }
        )
    }

    public var body: some View {
        Group {
            if isLocked {
                // A reply or an edit: the chip only shows the event's room.
                // Not a disabled menu, which would gray out the badge.
                ComposerTargetChipLabel(option: selected, reason: reason, isLocked: true)
                    .help(Text("A reply or an edit goes to the chat of its message"))
            } else {
                menu
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Send to \(selected.accessibilityTitle)"))
        .accessibilityValue(Text(reason.hintTitle))
    }

    private var menu: some View {
        Menu {
            Picker(selection: selection) {
                ForEach(options) { option in
                    ComposerTargetMenuItem(option: option)
                        .tag(option.id)
                }
            } label: {
                Text("Send To")
            }
            .pickerStyle(.inline)
            if reason == .chosen {
                Divider()
                Button("Choose Automatically") {
                    onSelect(nil)
                }
            }
        } label: {
            ComposerTargetChipLabel(option: selected, reason: reason, isLocked: false)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .help(Text("Choose the chat this message goes to"))
    }
}

/// The chip's visible content: badge, "To:", the target, the reason hint,
/// and a chevron.
struct ComposerTargetChipLabel: View {
    let option: ComposerTargetOption
    let reason: MergedSendTarget.Reason
    let isLocked: Bool

    var body: some View {
        HStack(spacing: ComposerTargetToken.spacing) {
            if let network = option.network {
                ChatListNetworkBadge(network: network, size: ComposerTargetToken.badgeSize)
            }
            Text("To:")
                .foregroundStyle(.secondary)
            title
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: ComposerTargetToken.nameMaxWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(reason.hintTitle)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if !isLocked {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .font(.callout)
        .padding(.horizontal, ComposerTargetToken.horizontalPadding)
        .frame(height: ComposerTargetToken.chipHeight)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(ComposerTargetToken.backgroundOpacity))
        )
        .contentShape(Capsule(style: .continuous))
    }

    /// "Slack • DevObsessed", or the name alone when the network is unknown.
    private var title: Text {
        if let network = option.network {
            return Text("\(network.displayName) • \(option.name)")
        }
        return Text(verbatim: option.name)
    }
}

/// One member room in the menu: the network badge and the name, with the
/// network name as a subtitle.
struct ComposerTargetMenuItem: View {
    let option: ComposerTargetOption

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Label {
            Text(verbatim: option.name)
            if let network = option.network {
                Text(network.displayName)
            }
        } icon: {
            if let network = option.network, let badge = ComposerTargetMenuItem.badgeImage(network, scale: displayScale) {
                badge
            }
        }
    }

    /// The network badge as an image, because a menu item draws only text
    /// and images, not arbitrary views.
    @MainActor
    static func badgeImage(_ network: ChatListNetwork, scale: CGFloat) -> Image? {
        let renderer = ImageRenderer(
            content: ChatListNetworkBadge(network: network, size: ComposerTargetToken.menuBadgeSize)
        )
        renderer.scale = scale
        #if os(macOS)
            return renderer.nsImage.map { Image(nsImage: $0) }
        #else
            return renderer.uiImage.map { Image(uiImage: $0) }
        #endif
    }
}

extension ComposerTargetOption {
    /// "DevObsessed on Slack", or the name alone, for VoiceOver.
    var accessibilityTitle: String {
        if let network {
            return String(localized: "\(name) on \(network.displayName)")
        }
        return name
    }
}

extension MergedSendTarget.Reason {
    /// The hint the chip shows for the reason.
    var hintTitle: LocalizedStringKey {
        switch self {
        case .chosen: "Chosen"
        case .recentActivity: "Last active"
        case .defaultRoom: "Default"
        case .reply: "Replying"
        case .edit: "Editing"
        }
    }
}

#Preview {
    ComposerTargetPicker(
        options: [
            ComposerTargetOption(id: "!a:davlin.io", name: "DevObsessed", network: .slack),
            ComposerTargetOption(id: "!b:davlin.io", name: "pizza box audit committee", network: .slack),
        ],
        selectedRoomId: "!a:davlin.io",
        reason: .recentActivity,
        onSelect: { _ in }
    )
    .padding()
}
