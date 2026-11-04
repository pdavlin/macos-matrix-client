import Foundation

/// The process that builds an SDK client (MATRIX-96).
public enum ClientProcess: Sendable {
    /// The app: the Mac app or the iOS app.
    case app
    /// The iOS Notification Service Extension.
    case notificationServiceExtension
}

/// The platform that a client runs on.
public enum ClientPlatform: Sendable {
    case macOS
    case iOS

    public static var current: ClientPlatform {
        #if os(iOS)
            .iOS
        #else
            .macOS
        #endif
    }
}

/// The SDK cross-process lock configuration of a client (MATRIX-96).
///
/// On iOS, the app and the Notification Service Extension open the same App
/// Group store and the same keychain session. Each process takes the store
/// locks and the OAuth refresh lock with its own holder name. The Mac app has
/// one process and keeps the FFI default (single process, no lock).
public enum CrossProcessLockChoice: Equatable, Sendable {
    /// Do not set a lock configuration. The FFI default is single process.
    case sdkDefault
    /// Multi-process locks with this holder name.
    case multiProcess(holderName: String)

    /// The holder name of the iOS app.
    public static let appHolderName = "app"
    /// The holder name of the iOS Notification Service Extension.
    public static let notificationServiceExtensionHolderName = "nse"

    public static func choice(for process: ClientProcess, on platform: ClientPlatform = .current) -> CrossProcessLockChoice {
        switch (platform, process) {
        case (.macOS, _):
            .sdkDefault
        case (.iOS, .app):
            .multiProcess(holderName: appHolderName)
        case (.iOS, .notificationServiceExtension):
            .multiProcess(holderName: notificationServiceExtensionHolderName)
        }
    }

    /// The SDK refuses to build a multi-process client without a session
    /// delegate.
    public var requiresSessionDelegate: Bool {
        self != .sdkDefault
    }
}
