import Foundation

// `Internals` exposes the record-mode resolution and `recordIssue` that
// `assertSnapshot` itself uses. The package pins SnapshotTesting exactly.
@_spi(Internals) import SnapshotTesting

/// The number of quiet attempts before the last, recorded attempt
/// (MATRIX-120, MATRIX-126).
let textFieldSnapshotQuietAttempts = 3

/// Asserts a snapshot with automatic retries, for suites that render SwiftUI
/// text fields (MATRIX-120, MATRIX-126).
///
/// In about one test process in eight, SwiftUI lays out one `TextField` with
/// the line height of a different font: a 17 pt field gets a 16 pt frame, a
/// 13 pt field gets an 18 pt or 20 pt frame. The `NSTextField` has the correct
/// font and the correct intrinsic height; only the frame from the SwiftUI
/// layout is wrong, so the text moves 2 pt. The wrong value is always the
/// height of a text field in another test's view. No relayout of the wrong
/// view corrects it. The cause is inside SwiftUI and is not known; it is not
/// in our code, and CI has not shown it.
///
/// What MATRIX-126 measured about recovery:
/// - A new view that is created after the wrong view is released is wrong
///   again. Four attempts in a row failed in 10 of 80 runs.
/// - The earlier design (one retry after a 1 s run-loop spin) failed on both
///   attempts in about 1 of 10 runs.
/// - When each wrong view stays alive, a later attempt passed in 40 of 40
///   cases (240 runs). In 34 of them only the last attempt passed.
///
/// So the helper keeps each failed view alive until the last attempt
/// completes, and it does not spin the run loop between attempts.
///
/// Use it in every suite that shows a text field. Every other suite keeps a
/// single attempt. A test that fails on all attempts is a real failure: the
/// last attempt is exactly the body of SnapshotTesting's `assertSnapshot`
/// (`verifySnapshot` plus `recordIssue`), so it records the usual issue with
/// the usual diff. When a retry passes, one line goes to stderr so retries
/// stay visible in logs.
///
/// The quiet attempts run with `record: .never`, so they never write a
/// reference. When the effective record mode is `.all`, there is no retry.
/// An unnamed call compares against `<test>.1`, so call this at most once per
/// test without a name.
@MainActor
func assertTextFieldSnapshot<Value>(
    of value: @autoclosure () -> Value,
    as snapshotting: Snapshotting<Value, some Any>,
    named name: String? = nil,
    record: SnapshotTestingConfiguration.Record? = nil,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    // Same resolution order as `verifySnapshot`.
    let effectiveRecord: SnapshotTestingConfiguration.Record =
        record ?? SnapshotTestingConfiguration.current?.record ?? _record
    // The failed views stay alive on purpose: see the measurements above.
    var failedValues: [Value] = []
    if effectiveRecord != .all {
        // A fixed name keeps these attempts off the per-test counter, so the
        // last attempt below still resolves to the same `<test>.1` reference.
        for _ in 0 ..< textFieldSnapshotQuietAttempts {
            let candidate = value()
            let failure: String? = verifySnapshot(
                of: candidate,
                as: snapshotting,
                named: name ?? "1",
                record: .never,
                fileID: fileID,
                file: filePath,
                testName: testName,
                line: line,
                column: column
            )
            guard failure != nil else {
                reportRetry(failedValues.count, fileID: fileID, testName: testName)
                return
            }
            failedValues.append(candidate)
        }
    }
    let retryFailure: String? = withExtendedLifetime(failedValues) {
        verifySnapshot(
            of: value(),
            as: snapshotting,
            named: name,
            record: record,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
    }
    guard let message = retryFailure else {
        reportRetry(failedValues.count, fileID: fileID, testName: testName)
        return
    }
    recordIssue(message, fileID: fileID, filePath: filePath, line: line, column: column)
}

private func reportRetry(_ failedAttempts: Int, fileID: StaticString, testName: String) {
    guard failedAttempts > 0 else { return }
    FileHandle.standardError.write(
        Data("MATRIX-120 snapshot retry passed after \(failedAttempts) failed: \(fileID) \(testName)\n".utf8)
    )
}
