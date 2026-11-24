import Models
import SwiftUI
import Tokens

/// Where a rail item is and what it is called, for the rail name peek
/// (MATRIX-227).
struct LabelRailItemAnchor {
    let bounds: Anchor<CGRect>
    let title: String
}

/// The rail items' places and names by their filter (MATRIX-227).
struct LabelRailItemAnchors: PreferenceKey {
    static var defaultValue: [ChatListRailFilter: LabelRailItemAnchor] {
        [:]
    }

    static func reduce(value: inout [ChatListRailFilter: LabelRailItemAnchor], nextValue: () -> [ChatListRailFilter: LabelRailItemAnchor]) {
        value.merge(nextValue()) { _, next in next }
    }
}

extension View {
    /// Reports a rail item's place and name, for the peek.
    func labelRailItemAnchor(_ filter: ChatListRailFilter, title: String) -> some View {
        anchorPreference(key: LabelRailItemAnchors.self, value: .bounds) { bounds in
            [filter: LabelRailItemAnchor(bounds: bounds, title: title)]
        }
    }
}

/// The name of a rail item, next to the rail (MATRIX-227): a capsule after
/// Indigo's `TimelineCapsuleView` feed-name peek.
///
/// It floats over the chat list beside the rail, so it draws on a material,
/// not on glass (CLAUDE.md hard rule 2), as the inbox toast does.
struct LabelRailNamePeekView: View {
    let title: String

    /// The space between the item and the capsule.
    static var gap: CGFloat { 4 }
    /// A longer name truncates.
    static var maxWidth: CGFloat { 220 }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: .capsule)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            // The capsule hugs the name; the frame only caps it.
            .frame(maxWidth: Self.maxWidth, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Shows the rail name peek next to its rail item, then collapses it when
/// its time is over (MATRIX-227).
///
/// The capsule grows out of the rail side: from `MotionToken.railPeekScale`
/// at its leading edge and `MotionToken.railPeekDistance` toward the rail,
/// on the settle spring, and collapses back the same way. A new key during
/// the peek collapses the old name and grows the new one. Under Reduce
/// Motion it fades in and out only. It takes no clicks.
struct LabelRailNamePeekOverlay: ViewModifier {
    let item: RailNamePeek.Item?
    let onExpire: @MainActor () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(LabelRailItemAnchors.self) { anchors in
                GeometryReader { proxy in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        if let item, let anchor = anchors[item.filter] {
                            let rect = proxy[anchor.bounds]
                            let leading = rect.maxX + LabelRailNamePeekView.gap
                            // An item scrolled out of the rail keeps its
                            // name inside the sidebar.
                            let midY = min(max(rect.midY, 0), proxy.size.height)
                            LabelRailNamePeekView(title: anchor.title)
                                .alignmentGuide(.leading) { _ in -leading }
                                .alignmentGuide(.top) { dimensions in -(midY - dimensions.height / 2) }
                                .transition(
                                    EntranceTransition(
                                        anchor: .leading,
                                        scale: MotionToken.railPeekScale,
                                        distance: MotionToken.railPeekDistance,
                                        reduceMotion: reduceMotion
                                    )
                                )
                                .id(item.id)
                        }
                    }
                    .animation(MotionToken.settleAnimation(reduceMotion: reduceMotion), value: item?.id)
                }
                .allowsHitTesting(false)
            }
            .task(id: item?.id) {
                guard let item else { return }
                do {
                    try await Task.sleep(until: item.hidesAt, clock: .continuous)
                } catch {
                    // A newer peek or a hide cancelled the wait.
                    return
                }
                onExpire()
            }
    }
}

public extension View {
    /// Shows the rail name peek beside the rail item it names (MATRIX-227).
    ///
    /// Put it on a view that holds the `LabelRail` and the chat list beside
    /// it, so the name can draw next to the rail.
    ///
    /// - Parameters:
    ///   - item: the shown name (`RailNamePeek.item`), or nil.
    ///   - onExpire: called when the name's time is over; the caller
    ///     collapses it with `RailNamePeek.expire(at:)`.
    func labelRailNamePeek(_ item: RailNamePeek.Item?, onExpire: @escaping @MainActor () -> Void) -> some View {
        modifier(LabelRailNamePeekOverlay(item: item, onExpire: onExpire))
    }
}
