import Models
import Testing

/// D-1 (approved 2026-09-01): Enter sends, Shift-Enter inserts a newline,
/// Cmd-Enter also sends. IME composition always wins over sending.
///
/// MATRIX-100 adds `.commandEnterSends`: Cmd-Enter sends, Enter and
/// Shift-Enter insert a newline. The IME, Option/Control, and non-Return
/// rules are the same in both modes.
struct ComposerKeyDecisionTests {
    typealias SendMode = ComposerKeyDecision.SendMode

    private func action(
        isReturnKey: Bool = true,
        hasMarkedText: Bool = false,
        shift: Bool = false,
        command: Bool = false,
        otherModifiers: Bool = false,
        mode: SendMode = .enterSends
    ) -> ComposerKeyDecision.Action {
        ComposerKeyDecision.action(
            isReturnKey: isReturnKey,
            hasMarkedText: hasMarkedText,
            shift: shift,
            command: command,
            otherModifiers: otherModifiers,
            mode: mode
        )
    }

    // MARK: - Enter sends (D-1 default)

    @Test func plainEnterSends() {
        #expect(action() == .send)
    }

    @Test func shiftEnterInsertsNewline() {
        #expect(action(shift: true) == .passthrough)
    }

    @Test func commandEnterSends() {
        #expect(action(command: true) == .send)
    }

    @Test func commandShiftEnterSends() {
        // Command wins: Cmd-Enter is an explicit send gesture whatever else
        // is held alongside it.
        #expect(action(shift: true, command: true) == .send)
    }

    // MARK: - Cmd-Enter sends (MATRIX-100)

    @Test func commandMode_plainEnterInsertsNewline() {
        #expect(action(mode: .commandEnterSends) == .passthrough)
    }

    @Test func commandMode_shiftEnterInsertsNewline() {
        #expect(action(shift: true, mode: .commandEnterSends) == .passthrough)
    }

    @Test func commandMode_commandEnterSends() {
        #expect(action(command: true, mode: .commandEnterSends) == .send)
    }

    @Test func commandMode_commandShiftEnterSends() {
        #expect(action(shift: true, command: true, mode: .commandEnterSends) == .send)
    }

    // MARK: - Rules shared by both modes

    @Test(arguments: SendMode.allCases)
    func enterDuringImeCompositionPassesThrough(mode: SendMode) {
        // Return with marked text commits the composition; it must not send.
        #expect(action(hasMarkedText: true, mode: mode) == .passthrough)
        #expect(action(hasMarkedText: true, shift: true, mode: mode) == .passthrough)
        #expect(action(hasMarkedText: true, command: true, mode: mode) == .passthrough)
        #expect(action(hasMarkedText: true, shift: true, command: true, mode: mode) == .passthrough)
        #expect(action(hasMarkedText: true, otherModifiers: true, mode: mode) == .passthrough)
    }

    @Test(arguments: SendMode.allCases)
    func optionOrControlEnterPassesThrough(mode: SendMode) {
        #expect(action(otherModifiers: true, mode: mode) == .passthrough)
        #expect(action(shift: true, otherModifiers: true, mode: mode) == .passthrough)
        #expect(action(command: true, otherModifiers: true, mode: mode) == .passthrough)
        #expect(action(shift: true, command: true, otherModifiers: true, mode: mode) == .passthrough)
    }

    @Test(arguments: SendMode.allCases)
    func nonReturnKeysPassThrough(mode: SendMode) {
        #expect(action(isReturnKey: false, mode: mode) == .passthrough)
        #expect(action(isReturnKey: false, shift: true, mode: mode) == .passthrough)
        #expect(action(isReturnKey: false, command: true, mode: mode) == .passthrough)
        #expect(action(isReturnKey: false, shift: true, command: true, mode: mode) == .passthrough)
    }

    // MARK: - Exhaustive truth table (2^5 inputs x 2 modes)

    /// Every input combination, so a future edit cannot change a cell that
    /// the named tests above happen not to cover.
    @Test(arguments: SendMode.allCases)
    func exhaustiveTruthTable(mode: SendMode) {
        for bits in 0 ..< 32 {
            let isReturnKey = bits & 1 != 0
            let hasMarkedText = bits & 2 != 0
            let shift = bits & 4 != 0
            let command = bits & 8 != 0
            let otherModifiers = bits & 16 != 0

            let eligible = isReturnKey && !hasMarkedText && !otherModifiers
            let expectedSend = switch mode {
            case .enterSends: eligible && (command || !shift)
            case .commandEnterSends: eligible && command
            }

            let result = action(
                isReturnKey: isReturnKey,
                hasMarkedText: hasMarkedText,
                shift: shift,
                command: command,
                otherModifiers: otherModifiers,
                mode: mode
            )
            #expect(
                result == (expectedSend ? .send : .passthrough),
                "bits=\(bits) mode=\(mode)"
            )
        }
    }

    // MARK: - API and storage contract

    /// The pre-M2 call site (no `mode:` argument) must keep D-1 behavior.
    @Test func defaultArgumentIsEnterSends() {
        for bits in 0 ..< 32 {
            let args = (
                isReturnKey: bits & 1 != 0,
                hasMarkedText: bits & 2 != 0,
                shift: bits & 4 != 0,
                command: bits & 8 != 0,
                otherModifiers: bits & 16 != 0
            )
            let legacy = ComposerKeyDecision.action(
                isReturnKey: args.isReturnKey,
                hasMarkedText: args.hasMarkedText,
                shift: args.shift,
                command: args.command,
                otherModifiers: args.otherModifiers
            )
            let explicit = ComposerKeyDecision.action(
                isReturnKey: args.isReturnKey,
                hasMarkedText: args.hasMarkedText,
                shift: args.shift,
                command: args.command,
                otherModifiers: args.otherModifiers,
                mode: .enterSends
            )
            #expect(legacy == explicit, "bits=\(bits)")
        }
    }

    @Test func defaultModeIsEnterSends() {
        #expect(SendMode.defaultMode == .enterSends)
    }

    /// Stored user settings: renaming the key or a raw value silently resets
    /// every user's choice.
    @Test func storageContractIsStable() {
        #expect(SendMode.storageKey == "composerSendMode")
        #expect(SendMode.enterSends.rawValue == "enterSends")
        #expect(SendMode.commandEnterSends.rawValue == "commandEnterSends")
        #expect(SendMode.allCases == [.enterSends, .commandEnterSends])
    }
}
