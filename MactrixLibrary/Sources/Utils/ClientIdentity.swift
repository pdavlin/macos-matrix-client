/// The kind of device the client runs on, as far as the homeserver device list
/// cares. Not `ClientPlatform` (MATRIX-96), which names only the OS.
public enum ClientDevice: Sendable, Equatable, CaseIterable {
    case macOS
    case iPhone
    case iPad
}

/// The device display name and user agent the client reports to the
/// homeserver (MATRIX-94). Pure so the iOS values are testable on the Mac.
public struct ClientIdentity: Sendable, Equatable {
    public let deviceDisplayName: String
    public let userAgent: String

    public init(platform: ClientDevice) {
        switch platform {
        case .macOS:
            deviceDisplayName = "Round"
            userAgent = "Round macOS"
        case .iPhone:
            deviceDisplayName = "Round (iPhone)"
            userAgent = "Round iOS"
        case .iPad:
            deviceDisplayName = "Round (iPad)"
            userAgent = "Round iOS"
        }
    }
}
