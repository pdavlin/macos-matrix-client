import Models
import OSLog
import SwiftUI

/// The work the New Chat screen hands back to the app (MATRIX-75).
///
/// Closures over neutral models, so the screen renders and snapshot-tests
/// without the SDK. The app target wires them to `MatrixClient`.
public struct NewChatActions {
    /// Searches the user directory for a query.
    public var search: @MainActor (_ query: String) async throws -> [NewChatPerson]
    /// Fetches the profile for an exact user ID.
    public var resolveProfile: @MainActor (_ userId: String) async throws -> NewChatPerson
    /// Opens or creates the chat. The app leaves the screen on success.
    public var start: @MainActor (_ request: NewChatStartRequest) async throws -> Void
    /// Joins a room from what was typed in the join field.
    public var join: @MainActor (_ address: String) async throws -> Void

    public init(
        search: @escaping @MainActor (_ query: String) async throws -> [NewChatPerson],
        resolveProfile: @escaping @MainActor (_ userId: String) async throws -> NewChatPerson,
        start: @escaping @MainActor (_ request: NewChatStartRequest) async throws -> Void,
        join: @escaping @MainActor (_ address: String) async throws -> Void
    ) {
        self.search = search
        self.resolveProfile = resolveProfile
        self.start = start
        self.join = join
    }
}

/// The editable state of a New Chat draft.
///
/// Public so snapshot tests can render a screen mid-flow; the app starts from
/// the empty draft.
public struct NewChatDraft {
    public var query: String
    public var selected: [NewChatPerson]
    /// Directory results for the latest settled query, in server order.
    public var searchResults: [NewChatPerson]
    /// The profile fetched for the query when it is an exact user ID.
    public var resolvedProfile: NewChatPerson?
    public var groupName: String
    public var isEncrypted: Bool
    public var isConfirmingEncryption: Bool
    public var joinAddress: String
    public var errorMessage: String?

    public init(
        query: String = "",
        selected: [NewChatPerson] = [],
        searchResults: [NewChatPerson] = [],
        resolvedProfile: NewChatPerson? = nil,
        groupName: String = "",
        isEncrypted: Bool = true,
        isConfirmingEncryption: Bool = false,
        joinAddress: String = "",
        errorMessage: String? = nil
    ) {
        self.query = query
        self.selected = selected
        self.searchResults = searchResults
        self.resolvedProfile = resolvedProfile
        self.groupName = groupName
        self.isEncrypted = isEncrypted
        self.isConfirmingEncryption = isConfirmingEncryption
        self.joinAddress = joinAddress
        self.errorMessage = errorMessage
    }
}

/// Beeper-style "Start new chat" draft, shown in the detail pane (MATRIX-75).
///
/// A To: token field over a result list, with leading actions for a new
/// group and for joining a room. This is content, not navigation chrome, so
/// it carries no glass.
public struct NewChatScreen: View {
    static let startErrorMessage = "Something went wrong while trying to start this chat."
    static let joinErrorMessage = "Something went wrong while trying to join this Matrix room."

    enum Field: Hashable {
        case to, groupName, joinAddress
    }

    enum Row: Identifiable {
        case newGroup, joinRoom
        case person(NewChatPerson)

        var id: String {
            switch self {
            case .newGroup: "action.newGroup"
            case .joinRoom: "action.joinRoom"
            case let .person(person): person.userId
            }
        }

        var isPerson: Bool {
            if case .person = self { return true }
            return false
        }
    }

    @Binding var mode: NewChatMode
    let recentContacts: [NewChatPerson]
    let ownUserId: String?
    let imageLoader: ImageLoader?
    let actions: NewChatActions

    @State var draft: NewChatDraft
    /// The keyboard selection, which Return acts on.
    @State var highlightedRowId: String?
    /// The row under the pointer. Visual only, so a resting pointer never
    /// changes what Return does.
    @State var hoveredRowId: String?
    @State var isSearching = false
    @State var isBusy = false
    @State var toSelection: TextSelection?
    @FocusState var focusedField: Field?

    public init(
        mode: Binding<NewChatMode>,
        recentContacts: [NewChatPerson],
        ownUserId: String?,
        imageLoader: ImageLoader?,
        actions: NewChatActions,
        draft: NewChatDraft = NewChatDraft()
    ) {
        self._mode = mode
        self.recentContacts = recentContacts
        self.ownUserId = ownUserId
        self.imageLoader = imageLoader
        self.actions = actions
        self._draft = State(initialValue: draft)
    }

    // MARK: - Derived state

    var trimmedQuery: String {
        draft.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var rows: [Row] {
        let selectedIds = Set(draft.selected.map(\.userId))

        guard !trimmedQuery.isEmpty else {
            let recents = NewChatResults.assemble(
                query: "", resolvedProfile: nil, searchResults: recentContacts,
                ownUserId: ownUserId, selectedUserIds: selectedIds
            )
            let leading: [Row] = mode == .direct ? [.newGroup, .joinRoom] : []
            return leading + recents.map(Row.person)
        }

        return NewChatResults.assemble(
            query: trimmedQuery, resolvedProfile: draft.resolvedProfile, searchResults: draft.searchResults,
            ownUserId: ownUserId, selectedUserIds: selectedIds
        ).map(Row.person)
    }

    /// The row Return activates: the hovered or arrowed row, else the first
    /// result while a query is typed.
    var effectiveHighlightId: String? {
        let rows = rows
        if let highlightedRowId, rows.contains(where: { $0.id == highlightedRowId }) {
            return highlightedRowId
        }
        return trimmedQuery.isEmpty ? nil : rows.first?.id
    }

    var startRequest: NewChatStartRequest? {
        NewChatStartRequest.make(
            mode: mode, selected: draft.selected, groupName: draft.groupName, isEncrypted: draft.isEncrypted
        )
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if mode == .join {
                joinContent
            } else {
                chatContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .overlay {
            if draft.isConfirmingEncryption {
                encryptionConfirmOverlay
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(phases: .down, action: typeToFocus)
        .navigationTitle(navigationTitle)
        .onAppear { focusedField = mode == .join ? .joinAddress : .to }
        .onChange(of: mode) { _, newMode in
            highlightedRowId = nil
            draft.errorMessage = nil
            draft.isConfirmingEncryption = false
            focusedField = newMode == .join ? .joinAddress : .to
        }
        .onChange(of: draft.query) { _, _ in highlightedRowId = nil }
        .task(id: SearchKey(query: trimmedQuery, mode: mode)) { await runSearch() }
    }

    var navigationTitle: String {
        switch mode {
        case .direct: "New Chat"
        case .group: "New Group"
        case .join: "Join a Matrix Room"
        }
    }

    var chatContent: some View {
        VStack(spacing: 0) {
            if mode == .group {
                groupHeader
                Divider()
            }
            toField
            Divider()
            resultList
            Divider()
            footer
        }
    }

    var groupHeader: some View {
        HStack(spacing: 8) {
            backButton
            TextField("Group name (optional)", text: $draft.groupName)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold))
                .focused($focusedField, equals: .groupName)
                .onSubmit { focusedField = .to }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    var backButton: some View {
        Button {
            mode = .direct
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back")
        .accessibilityLabel("Back")
    }

    var toField: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("To:")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                if !draft.selected.isEmpty {
                    NewChatFlowLayout {
                        ForEach(draft.selected) { person in
                            NewChatPill(person: person, imageLoader: imageLoader) { remove(person) }
                        }
                    }
                }

                TextField("Name or Matrix ID, like @name:server", text: $draft.query, selection: $toSelection)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($focusedField, equals: .to)
                    .onSubmit(handleReturn)
                    .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                    .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                    .onKeyPress(.delete, action: removeLastOnEmptyQuery)
            }
        }
        .padding(12)
    }
}

// MARK: - Results, footer, and confirm

extension NewChatScreen {
    var resultList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    resultRows
                }
                .padding(8)
            }
            .onChange(of: highlightedRowId) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    @ViewBuilder
    var resultRows: some View {
        let rows = rows
        let personRows = rows.filter(\.isPerson)
        let highlight = effectiveHighlightId

        ForEach(rows.filter { !$0.isPerson }) { row in
            rowButton(row, isHighlighted: row.id == highlight || row.id == hoveredRowId)
                .id(row.id)
        }

        if !personRows.isEmpty {
            sectionLabel
        }

        ForEach(personRows) { row in
            rowButton(row, isHighlighted: row.id == highlight || row.id == hoveredRowId)
                .id(row.id)
        }

        if !trimmedQuery.isEmpty, personRows.isEmpty {
            Text(isSearching ? "Searching..." : "No people found")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    @ViewBuilder
    var sectionLabel: some View {
        Text(trimmedQuery.isEmpty ? "Recent" : "People")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    func rowButton(_ row: Row, isHighlighted: Bool) -> some View {
        Button {
            activate(row)
        } label: {
            switch row {
            case .newGroup:
                NewChatActionRow(title: "New Group", systemImage: "person.2", isHighlighted: isHighlighted)
            case .joinRoom:
                NewChatActionRow(title: "Join a Matrix room", systemImage: "number", isHighlighted: isHighlighted)
            case let .person(person):
                NewChatPersonRow(person: person, imageLoader: imageLoader, isHighlighted: isHighlighted)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredRowId = row.id
            } else if hoveredRowId == row.id {
                hoveredRowId = nil
            }
        }
    }

    var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage = draft.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            Spacer()
            NewChatPrimaryButton(
                title: isBusy ? "Starting..." : (mode == .group ? "Start group chat" : "Start chat"),
                isEnabled: startRequest != nil && !isBusy,
                action: beginStart
            )
        }
        .padding(12)
    }

    var encryptionConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
                .onTapGesture { draft.isConfirmingEncryption = false }
            NewChatEncryptionConfirm(
                isEncrypted: $draft.isEncrypted,
                isBusy: isBusy,
                onCancel: { draft.isConfirmingEncryption = false },
                onConfirm: confirmGroup
            )
        }
    }
}

/// The identity of a search: a new value restarts the debounced task.
private struct SearchKey: Hashable {
    let query: String
    let mode: NewChatMode
}

#Preview {
    @Previewable @State var mode = NewChatMode.direct
    NewChatScreen(
        mode: $mode,
        recentContacts: [NewChatPerson(userId: "@alice:example.org", displayName: "Alice")],
        ownUserId: "@me:example.org",
        imageLoader: nil,
        actions: NewChatActions(
            search: { _ in [] },
            resolveProfile: { NewChatPerson(userId: $0) },
            start: { _ in },
            join: { _ in }
        )
    )
    .frame(width: 560, height: 420)
}
