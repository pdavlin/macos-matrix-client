import Foundation

/// Why the crypto layer could not decrypt an event.
///
/// One case per SDK `UtdCause`, mirrored here so the row layer never imports
/// the FFI. The app target maps the SDK value onto this type; a new SDK case
/// fails that mapping's build rather than silently rendering a wrong reason.
///
/// The app must never derive a cause of its own: crypto owns UTD attribution
/// (hard rule 1). An encrypted message that carries no attribution — an Olm
/// message, or an algorithm the SDK does not recognise — maps to `.unknown`,
/// which is the SDK's own value for "no attribution".
public enum UnableToDecryptCause: Hashable, Sendable, CaseIterable {
    case unknown
    case sentBeforeWeJoined
    case verificationViolation
    case unsignedDevice
    case unknownDevice
    case historicalMessageAndBackupIsDisabled
    case withheldForUnverifiedOrInsecureDevice
    case withheldBySender
    case historicalMessageAndDeviceIsUnverified

    /// A stable, greppable name for the cause, written to the unified log.
    ///
    /// Kept distinct from `displayText` so a log predicate stays valid when
    /// the reader-facing wording changes.
    public var logLabel: String {
        switch self {
        case .unknown:
            "unknown"
        case .sentBeforeWeJoined:
            "sent-before-we-joined"
        case .verificationViolation:
            "verification-violation"
        case .unsignedDevice:
            "unsigned-device"
        case .unknownDevice:
            "unknown-device"
        case .historicalMessageAndBackupIsDisabled:
            "historical-message-and-backup-is-disabled"
        case .withheldForUnverifiedOrInsecureDevice:
            "withheld-for-unverified-or-insecure-device"
        case .withheldBySender:
            "withheld-by-sender"
        case .historicalMessageAndDeviceIsUnverified:
            "historical-message-and-device-is-unverified"
        }
    }

    /// The reason shown under an undecryptable message.
    ///
    /// Each string restates its own case and claims nothing further. `.unknown`
    /// deliberately has no text: the SDK assigned no cause, so the row states
    /// the failure alone.
    public var displayText: String? {
        switch self {
        case .unknown:
            nil
        case .sentBeforeWeJoined:
            String(localized: "Sent before you joined this room")
        case .verificationViolation:
            String(localized: "The sender's verified identity changed")
        case .unsignedDevice:
            String(localized: "Sent from a device the sender has not signed")
        case .unknownDevice:
            String(localized: "Sent from a device this client does not know")
        case .historicalMessageAndBackupIsDisabled:
            String(localized: "Historical message, and key backup is off")
        case .withheldForUnverifiedOrInsecureDevice:
            String(localized: "Keys were withheld from unverified or insecure devices")
        case .withheldBySender:
            String(localized: "The sender withheld the keys")
        case .historicalMessageAndDeviceIsUnverified:
            String(localized: "Historical message, and this device is not verified")
        }
    }
}
