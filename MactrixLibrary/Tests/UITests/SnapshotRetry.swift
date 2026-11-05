import Foundation

// `Internals` exposes the record-mode resolution and `recordIssue` that
// `assertSnapshot` itself uses. The package pins SnapshotTesting exactly.
@_spi(Internals) import SnapshotTesting

/// How long the main run loop spins between a failed first attempt and the
/// retry (MATRIX-120). An immediate retry was not enough: in a 20-run sample
/// (run 19), `LabelSnapshotTests.editSheetNew` failed on both attempts with
/// the race signature (same 880x1006 px size, 7238 px different in rows 98
/// to 157, the text-field area). The race window was longer than one render.
let textFieldSnapshotRetryDelay: TimeInterval = 1.0

/// Asserts a snapshot with one automatic retry, for suites that render
/// AppKit text fields (MATRIX-120).
///
/// In about one test process in seven, AppKit text fields render 2 pt taller
/// per line for a short, random time: the glyphs are identical, and the extra
/// space is only at the bottom of each line. An investigation of 100+ test
/// processes found no cause in our code and no app path, and CI has not shown
/// it. This retry hides only that race.
///
/// Use it ONLY in suites that show AppKit text fields. Every other suite keeps
/// a single attempt. A test that fails twice is a real failure: the second
/// attempt is exactly the body of SnapshotTesting's `assertSnapshot`
/// (`verifySnapshot` plus `recordIssue`), so it records the usual issue with
/// the usual diff. When the retry passes, one line goes to stderr so retries
/// stay visible in logs.
///
/// After a failed first attempt, the helper spins the main run loop for
/// `textFieldSnapshotRetryDelay` before it re-creates the view and retries.
///
/// The first attempt runs with `record: .never`, so it never writes a
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
    var firstAttemptFailed = false
    if effectiveRecord != .all {
        // A fixed name keeps the first attempt off the per-test counter, so
        // the retry below still resolves to the same `<test>.1` reference.
        let firstFailure: String? = verifySnapshot(
            of: value(),
            as: snapshotting,
            named: name ?? "1",
            record: .never,
            fileID: fileID,
            file: filePath,
            testName: testName,
            line: line,
            column: column
        )
        guard firstFailure != nil else { return }
        firstAttemptFailed = true
        RunLoop.main.run(until: Date().addingTimeInterval(textFieldSnapshotRetryDelay))
    }
    let retryFailure: String? = verifySnapshot(
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
    guard let message = retryFailure else {
        if firstAttemptFailed {
            FileHandle.standardError.write(
                Data("MATRIX-120 snapshot retry passed: \(fileID) \(testName)\n".utf8)
            )
        }
        return
    }
    recordIssue(message, fileID: fileID, filePath: filePath, line: line, column: column)
}
