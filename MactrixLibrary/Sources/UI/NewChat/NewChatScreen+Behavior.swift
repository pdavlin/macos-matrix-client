import Models
import OSLog
import SwiftUI

// MARK: - Join mode

extension NewChatScreen {
    var joinContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                backButton
                Text("Join a Matrix room")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 44)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                TextField("Room address or Matrix link", text: $draft.joinAddress)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .focused($focusedField, equals: .joinAddress)
                    .onSubmit(submitJoin)

                Text("For example #room:example.org, !roomid:example.org, or a matrix.to link.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                if let errorMessage = draft.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }

                HStack {
                    Spacer()
                    Button(isBusy ? "Joining..." : "Join", action: submitJoin)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(draft.joinAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)
                }
            }
            .padding(16)
            .frame(maxWidth: 520, alignment: .leading)
        }
    }

    func submitJoin() {
        let address = draft.joinAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, !isBusy else { return }

        isBusy = true
        draft.errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await actions.join(address)
            } catch {
                Logger.viewCycle.error("new chat: join failed for \(address): \(error)")
                draft.errorMessage = Self.joinErrorMessage
            }
        }
    }
}

// MARK: - Search

extension NewChatScreen {
    /// Debounced (300 ms) directory search for the current query.
    ///
    /// Runs as a `.task(id:)`, so a new keystroke cancels the previous
    /// search. The exact user ID row does not wait for this: `rows` builds it
    /// from the typed text, and this only fills in its name and avatar.
    func runSearch() async {
        let query = trimmedQuery
        guard mode != .join, !query.isEmpty else {
            isSearching = false
            return
        }

        isSearching = true
        do {
            try await Task.sleep(for: .milliseconds(300))
        } catch {
            return
        }

        var results: [NewChatPerson] = []
        do {
            results = try await actions.search(query)
        } catch is CancellationError {
            return
        } catch {
            Logger.viewCycle.error("new chat: user search failed: \(error)")
        }

        var resolved: NewChatPerson?
        if let exactId = MatrixUserID.parse(query), !results.contains(where: { $0.userId == exactId }) {
            do {
                resolved = try await actions.resolveProfile(exactId)
            } catch {
                // Bridge bots often expose no profile. The bare ID row stays
                // and can still start the chat.
                Logger.viewCycle.info("new chat: no profile for \(exactId): \(error)")
            }
        }

        guard !Task.isCancelled else { return }
        draft.searchResults = results
        draft.resolvedProfile = resolved
        isSearching = false
    }
}

// MARK: - Selection and keyboard

extension NewChatScreen {
    func activate(_ row: Row) {
        switch row {
        case .newGroup:
            mode = .group
        case .joinRoom:
            mode = .join
        case let .person(person):
            select(person)
        }
    }

    func select(_ person: NewChatPerson) {
        draft.selected.append(person)
        // A direct chat has one person; a second pill turns the draft into a
        // group rather than leaving Start disabled.
        if mode == .direct, draft.selected.count > 1 {
            mode = .group
        }
        draft.query = ""
        draft.searchResults = []
        draft.resolvedProfile = nil
        draft.errorMessage = nil
        highlightedRowId = nil
        focusedField = .to
    }

    func remove(_ person: NewChatPerson) {
        draft.selected.removeAll { $0.userId == person.userId }
        focusedField = .to
    }

    func removeLastOnEmptyQuery() -> KeyPress.Result {
        guard draft.query.isEmpty, !draft.selected.isEmpty else { return .ignored }
        draft.selected.removeLast()
        return .handled
    }

    func moveHighlight(by offset: Int) -> KeyPress.Result {
        let rows = rows
        guard !rows.isEmpty else { return .ignored }

        let next: Int = if let current = effectiveHighlightId.flatMap({ id in rows.firstIndex { $0.id == id } }) {
            min(max(current + offset, 0), rows.count - 1)
        } else {
            offset > 0 ? 0 : rows.count - 1
        }
        highlightedRowId = rows[next].id
        return .handled
    }

    /// Return in the To: field: take the keyboard-highlighted row, else start.
    func handleReturn() {
        if let id = effectiveHighlightId, let row = rows.first(where: { $0.id == id }) {
            activate(row)
        } else {
            beginStart()
        }
    }

    /// A printable key typed while nothing has focus goes to the To: field.
    func typeToFocus(_ press: KeyPress) -> KeyPress.Result {
        guard mode != .join, focusedField == nil, !draft.isConfirmingEncryption else { return .ignored }
        guard press.modifiers.isDisjoint(with: [.command, .control, .option]) else { return .ignored }

        let characters = press.characters
        let isPrintable = characters.allSatisfy { character in
            character == " " || character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        }
        guard !characters.isEmpty, isPrintable else { return .ignored }

        draft.query.append(characters)
        focusedField = .to
        // A text field selects its contents when it becomes first responder;
        // put the caret back at the end once focus has landed.
        Task { toSelection = TextSelection(insertionPoint: draft.query.endIndex) }
        return .handled
    }
}

// MARK: - Start

extension NewChatScreen {
    func beginStart() {
        guard let request = startRequest, !isBusy else { return }
        if case .group = request {
            focusedField = nil
            draft.isConfirmingEncryption = true
            return
        }
        start(request)
    }

    func confirmGroup() {
        guard let request = startRequest, !isBusy else { return }
        start(request)
    }

    func start(_ request: NewChatStartRequest) {
        isBusy = true
        draft.errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await actions.start(request)
            } catch {
                Logger.viewCycle.error("new chat: start failed: \(error)")
                draft.errorMessage = Self.startErrorMessage
            }
            draft.isConfirmingEncryption = false
        }
    }
}
