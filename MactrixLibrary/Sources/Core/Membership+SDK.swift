import MatrixRustSDK
import Models

public extension MatrixRustSDK.Membership {
    /// The neutral model of the user's membership (MATRIX-116).
    var asModel: Models.Membership {
        switch self {
        case .joined: .joined
        case .invited: .invited
        case .left: .left
        case .knocked: .knocked
        case .banned: .banned
        }
    }
}
