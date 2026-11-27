import Foundation
import MatrixRustSDK
import Models

/// The session side of thread follow (MATRIX-261). The rules live in
/// `Models` (`ThreadFollow.swift`) and the state in `ThreadFollowStore`.
extension MatrixClient {
    /// Gives `ThreadFollowStore.shared` this session's rooms and the SDK's
    /// `Client.resetSupportedVersions() async throws` (docs/ffi line 1421).
    /// Call it once the SDK client exists.
    func configureThreadFollow() {
        guard let sdkClient: ClientProtocol = client else { return }
        ThreadFollowStore.shared.configure(
            callsForRoom: { roomId in
                guard let room = try? sdkClient.getRoom(roomId: roomId) else { return nil }
                return ThreadSubscriptionCalls(room: room)
            },
            resetVersions: { try await sdkClient.resetSupportedVersions() }
        )
    }

    /// Stops the calls and drops the records on sign-out.
    func resetThreadFollow() {
        ThreadFollowStore.shared.configure(callsForRoom: nil, resetVersions: nil)
        ThreadFollowStore.shared.removeAll()
    }
}
