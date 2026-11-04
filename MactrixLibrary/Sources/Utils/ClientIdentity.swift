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
            deviceDisplayName = "Mactrix"
            userAgent = "Mactrix macOS"
        case .iPhone:
            deviceDisplayName = "Mactrix (iPhone)"
            userAgent = "Mactrix iOS"
        case .iPad:
            deviceDisplayName = "Mactrix (iPad)"
            userAgent = "Mactrix iOS"
        }
    }
}
