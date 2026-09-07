import Foundation
import MatrixRustSDK
import Models
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
            cause=\(Models.UnableToDecryptCause(info.cause).logLabel, privacy: .public) \
            lateDecryptMs=\(info.timeToDecryptMs.map(String.init) ?? "none", privacy: .public) \
            eventLocalAgeMs=\(info.eventLocalAgeMillis, privacy: .public) \
            userTrustsOwnIdentity=\(info.userTrustsOwnIdentity, privacy: .public) \
            senderHomeserver=\(info.senderHomeserver, privacy: .public) \
            ownHomeserver=\(info.ownHomeserver ?? "none", privacy: .public)
            """
        )
    }
}
