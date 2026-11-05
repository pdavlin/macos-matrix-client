import Foundation

/// Decides whether a sidebar space row stands for a room the account has
/// already joined, so the row never offers "Join" for it (MATRIX-121).
///
/// Three sources can say "joined", and any one of them is enough:
/// - the SDK's own membership on the space hierarchy item (`SpaceRoom.state`).
///   The top-level rows come from `SpaceService.subscribeToTopLevelJoinedSpaces`,
///   so for them this is the reliable answer;
/// - the room is in the window's room list;
/// - `Client.getRoom(roomId:)` reports `.joined` for it.
///
/// The room list alone is not enough: since MATRIX-67 it is the inbox chat
/// list, which holds no spaces and drops filtered-out rooms.
public enum SpaceRowMembership {
    public static func isJoined(
        hierarchyStateIsJoined: Bool,
        isInRoomList: Bool,
        clientReportsJoined: Bool
    ) -> Bool {
        hierarchyStateIsJoined || isInRoomList || clientReportsJoined
    }
}
