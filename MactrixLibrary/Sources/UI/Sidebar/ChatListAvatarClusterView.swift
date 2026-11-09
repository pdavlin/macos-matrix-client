import Models
import SwiftUI
import Tokens

/// A group avatar drawn as a cluster of bubbles, one per hero (MATRIX-129).
///
/// `ChatListAvatar` shows it for a group with no room avatar and two or more
/// visible heroes. Each bubble sits in a slot from `ChatListToken.clusterSlots`:
/// a circle of `scale * size` whose center is `offset * size` from the
/// avatar's center. A bubble shows the hero's avatar image, else the hero's
/// colored initials.
///
/// The cluster is not clipped as a whole: the bubbles must stay whole, and
/// the slots keep them inside the avatar square.
struct ChatListAvatarClusterView: View {
    let cluster: ChatListAvatarCluster
    /// The side of the avatar square in points.
    let size: CGFloat
    let imageLoader: ImageLoader?

    /// The cluster mode for an avatar side: full (five bubbles and the "+N"
    /// label) from `ChatListToken.clusterFullModeMinimumSize` up, else
    /// compact (three bubbles).
    static func mode(forSize size: CGFloat) -> ChatListAvatarCluster.Mode {
        size >= ChatListToken.clusterFullModeMinimumSize ? .full : .compact
    }

    var body: some View {
        let slots = ChatListToken.clusterSlots
        ZStack {
            // The slot is the face's position, so the index is a stable ID.
            ForEach(0 ..< min(cluster.faces.count, slots.count), id: \.self) { (index: Int) in
                bubble(for: cluster.faces[index], diameter: diameter(slots[index]))
                    .offset(offset(slots[index]))
            }
            if let overflowText = cluster.overflowText, cluster.faces.count < slots.count {
                Text(overflowText)
                    .font(.system(size: size * ChatListToken.clusterOverflowFontRatio, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .offset(offset(slots[cluster.faces.count]))
            }
        }
        .frame(width: size, height: size)
    }

    /// One hero's bubble: a circle of the given diameter with the hero's
    /// image, or the hero's colored initials while it loads or when there is
    /// none.
    private func bubble(for hero: ChatListHero, diameter: CGFloat) -> some View {
        let initials = ChatListInitials.person(displayName: hero.displayName, userId: hero.userId)
        return AvatarImage(avatarUrl: hero.avatarUrl, imageLoader: imageLoader) {
            ChatListAvatarPlaceholder(initials: initials, size: diameter)
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private func diameter(_ slot: ChatListToken.ClusterSlot) -> CGFloat {
        size * slot.scale
    }

    private func offset(_ slot: ChatListToken.ClusterSlot) -> CGSize {
        CGSize(width: size * slot.offsetX, height: size * slot.offsetY)
    }
}

#Preview {
    let heroes: [ChatListHero] = [
        ChatListHero(userId: "@alice:example.org", displayName: "Alice Liddell"),
        ChatListHero(userId: "@bob:example.org", displayName: "Bob Ross"),
        ChatListHero(userId: "@carol:example.org", displayName: "Carol"),
        ChatListHero(userId: "@dan:example.org", displayName: "Dan Brown"),
        ChatListHero(userId: "@erin:example.org", displayName: "Erin"),
    ]
    HStack(spacing: 16) {
        ChatListAvatarClusterView(
            cluster: ChatListAvatarCluster(heroes: heroes, otherMemberCount: 5, mode: .compact),
            size: 36,
            imageLoader: nil
        )
        ChatListAvatarClusterView(
            cluster: ChatListAvatarCluster(heroes: heroes, otherMemberCount: 12, mode: .full),
            size: 44,
            imageLoader: nil
        )
    }
    .padding()
}
