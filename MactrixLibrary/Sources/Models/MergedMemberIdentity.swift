import Foundation

/// What tells the member chats of one merged chat apart (MATRIX-147).
///
/// The members of a merged chat are chats with one person, so they share a
/// title. The network tells two bridges apart; the account tells two chats of
/// one network apart: the Slack workspace, read as the name of the space the
/// bridge puts the chat in. A chat with neither falls back to the other
/// person's Matrix ID, then to the room's name.
///
/// ```swift
/// MergedMemberIdentity(network: .slack, parentNames: ["DevObsessed"], peerUserId: nil, roomName: "Seth")
///     .detail // "Slack • DevObsessed"
/// MergedMemberIdentity(network: nil, parentNames: [], peerUserId: "@seth:example.org", roomName: "Seth")
///     .detail // "@seth:example.org"
/// ```
public struct MergedMemberIdentity: Hashable, Sendable {
    /// The chat's bridged network (`ChatListNetwork.detect`), or nil.
    public var network: ChatListNetwork?
    /// The account the chat belongs to on its network, for example the Slack
    /// workspace "DevObsessed", or nil when the chat is in no named space.
    public var account: String?
    /// What names the chat when it has no account: the other person's Matrix
    /// ID, else the room's name.
    public var fallbackName: String?

    /// - Parameters:
    ///   - network: the chat's network, from the chat list's badge logic.
    ///   - parentNames: the names of the joined spaces that hold the chat.
    ///     The account is the first name that is not blank and is not the
    ///     network's own name (a bridge's "Slack" space says nothing new).
    ///   - peerUserId: the other person's Matrix user ID, when known.
    ///   - roomName: the room's display name.
    public init(network: ChatListNetwork?, parentNames: [String], peerUserId: String?, roomName: String?) {
        self.network = network
        account = parentNames.lazy
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { name in
                guard !name.isEmpty else { return false }
                guard let network else { return true }
                return name.caseInsensitiveCompare(network.displayName) != .orderedSame
            }
        fallbackName = [peerUserId, roomName].lazy
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The identity of a chat-list row.
    ///
    /// - Parameters:
    ///   - row: the member chat's row.
    ///   - parentNames: see `init(network:parentNames:peerUserId:roomName:)`.
    public init(row: ChatListRowModel, parentNames: [String]) {
        self.init(
            network: row.network,
            parentNames: parentNames,
            peerUserId: row.heroes.first?.userId,
            roomName: nil
        )
    }

    /// The part that tells this chat from the others of its network: the
    /// account, or the fallback name when the network is not known. Nil when
    /// the network alone is all that is known.
    public var distinguishingName: String? {
        account ?? (network == nil ? fallbackName : nil)
    }

    /// The whole identity as one line: "Slack • DevObsessed", "Slack",
    /// "DevObsessed", or "@seth:example.org". Nil when nothing is known.
    public var detail: String? {
        switch (network, distinguishingName) {
        case let (network?, name?): "\(network.displayName) • \(name)"
        case let (network?, nil): network.displayName
        case let (nil, name?): name
        case (nil, nil): nil
        }
    }
}
