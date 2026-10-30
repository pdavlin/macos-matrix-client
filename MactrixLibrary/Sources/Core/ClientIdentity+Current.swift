#if os(iOS)
    import UIKit
#endif
import Utils

@MainActor
extension ClientIdentity {
    /// The identity for the platform this build runs on (MATRIX-94).
    static var current: ClientIdentity {
        #if os(iOS)
            ClientIdentity(platform: UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone)
        #else
            ClientIdentity(platform: .macOS)
        #endif
    }
}
