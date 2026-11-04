import Foundation
import MatrixRustSDK
import Models
import OSLog

@MainActor @Observable
public final class AppState {
    public var matrixClient: MatrixClient?

    public init() {}

    public func reset() async throws {
        do {
            try await matrixClient?.reset()
        } catch {
            Logger.viewCycle.error("Failed to reset matrix client: \(error)")
        }
        matrixClient = nil
    }
}
