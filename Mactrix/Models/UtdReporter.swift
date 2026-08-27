import Foundation
import MatrixRustSDK
import OSLog

/// Records every "unable to decrypt" event the SDK reports.
///
/// The crypto layer owns UTD attribution: it decides whether a missing key is a
/// pre-join message, a device-historical message with no usable backup, an
/// unverified device, or a genuine bug. This type only writes what the SDK
/// reports to the unified log. It never inspects an event or guesses a cause.
///
/// Two switches gate the reports:
///   - `Client.setUtdDelegate` installs this delegate. The SDK errors if a
///     delegate is already set, so `MatrixClient.startSync` calls it once.
///   - `TimelineConfiguration.reportUtds` decides, per timeline instance,
///     whether that timeline forwards its UTDs here.
///
/// Read the records back with:
/// ```
/// log show --last 30m --predicate 'subsystem == "io.davlin.matrixclient" AND category == "utd"'
/// ```
final class UtdReporter: UnableToDecryptDelegate {
    func onUtd(info: UnableToDecryptInfo) {
        // Every field logged here is a diagnostic identifier, not a secret: an
        // event ID, a cause discriminant, two durations, a trust flag, and
        // server names. They are marked public so the records stay readable in
        // `log show` without attaching a debugger.
        Logger.utd.error(
            """
            UTD event=\(info.eventId, privacy: .public) \
            cause=\(Self.describe(info.cause), privacy: .public) \
            lateDecryptMs=\(info.timeToDecryptMs.map(String.init) ?? "none", privacy: .public) \
            eventLocalAgeMs=\(info.eventLocalAgeMillis, privacy: .public) \
            userTrustsOwnIdentity=\(info.userTrustsOwnIdentity, privacy: .public) \
            senderHomeserver=\(info.senderHomeserver, privacy: .public) \
            ownHomeserver=\(info.ownHomeserver ?? "none", privacy: .public)
            """
        )
    }

    /// A stable, greppable name for each cause.
    ///
    /// `UtdCause` has no `description` in the generated bindings, and the app
    /// must not invent its own attribution, so this maps one to one onto the
    /// SDK's cases. A new SDK case fails the build here rather than logging a
    /// wrong label.
    private static func describe(_ cause: UtdCause) -> String {
        switch cause {
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
}
