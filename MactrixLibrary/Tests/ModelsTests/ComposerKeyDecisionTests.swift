import Models
import Testing

/// D-1 (approved 2026-09-01): Enter sends, Shift-Enter inserts a newline,
/// Cmd-Enter also sends. IME composition always wins over sending.
struct ComposerKeyDecisionTests {
    private func action(
        isReturnKey: Bool = true,
        hasMarkedText: Bool = false,
        shift: Bool = false,
        command: Bool = false,
        otherModifiers: Bool = false
    ) -> ComposerKeyDecision.Action {
        ComposerKeyDecision.action(
            isReturnKey: isReturnKey,
            hasMarkedText: hasMarkedText,
            shift: shift,
            command: command,
            otherModifiers: otherModifiers
        )
    }

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

    @Test func enterDuringImeCompositionPassesThrough() {
        // Return with marked text commits the composition; it must not send.
        #expect(action(hasMarkedText: true) == .passthrough)
        #expect(action(hasMarkedText: true, command: true) == .passthrough)
    }

    @Test func optionOrControlEnterPassesThrough() {
        #expect(action(otherModifiers: true) == .passthrough)
        #expect(action(shift: true, otherModifiers: true) == .passthrough)
    }

    @Test func nonReturnKeysPassThrough() {
        #expect(action(isReturnKey: false) == .passthrough)
        #expect(action(isReturnKey: false, command: true) == .passthrough)
    }
}
