#if os(macOS)
    import AppKit
#endif
import Models
import OSLog
import SwiftUI

/// The work the quick switcher hands back to the app (MATRIX-114).
///
/// Build it with `navigate(...)` for ⌘K or `picker(onPick:)` for a caller
/// that wants a room back (MATRIX-112 forward). Closures over neutral
/// models, so the sheet renders and snapshot-tests without the SDK.
public struct QuickSwitcherActions {
    /// What the switcher is for.
    public let mode: QuickSwitcherMode
    /// Searches the user directory. Navigate mode only.
    let searchPeople: @MainActor (_ query: String) async throws -> [NewChatPerson]
    /// Shows a room in this window.
    let openRoom: (@MainActor (_ roomId: String) async throws -> Void)?
    /// Opens the existing DM with a person, or creates one, and shows it.
    let startDirectChat: (@MainActor (_ userId: String) async throws -> Void)?
    /// ⌥-Return: shows a room in its own window (MATRIX-116). ⌥-Return does
    /// nothing while it is `nil`.
    let openRoomInNewWindow: (@MainActor (_ roomId: String) async throws -> Void)?
    /// Hands a room back to the caller. Picker mode only.
    let pickRoom: (@MainActor (_ roomId: String) -> Void)?

    /// ⌘K: rooms and people. Picking a room opens it; picking a person opens
    /// or starts the DM.
    ///
    /// - Parameters:
    ///   - searchPeople: the user directory search (New Chat's path).
    ///   - openRoom: shows a room in this window.
    ///   - startDirectChat: New Chat's start path for one person.
    ///   - openRoomInNewWindow: ⌥-Return, the room in its own window
    ///     (MATRIX-116). Optional, so a caller without windows leaves it out.
    public static func navigate(
        searchPeople: @escaping @MainActor (_ query: String) async throws -> [NewChatPerson],
        openRoom: @escaping @MainActor (_ roomId: String) async throws -> Void,
        startDirectChat: @escaping @MainActor (_ userId: String) async throws -> Void,
        openRoomInNewWindow: (@MainActor (_ roomId: String) async throws -> Void)? = nil
    ) -> QuickSwitcherActions {
        QuickSwitcherActions(
            mode: .navigate,
            searchPeople: searchPeople,
            openRoom: openRoom,
            startDirectChat: startDirectChat,
            openRoomInNewWindow: openRoomInNewWindow,
            pickRoom: nil
        )
    }

    /// Picker mode: rooms only, and the picked room ID goes to `onPick`
    /// instead of opening. The sheet closes after the pick.
    ///
    /// ```swift
    /// .sheet(isPresented: $isPickingTarget) {
    ///     QuickSwitcherView(
    ///         rooms: directory.rooms, currentRoomId: nil, ownUserId: nil, imageLoader: client,
    ///         actions: .picker { roomId in forward(to: roomId) }
    ///     )
    /// }
    /// ```
    public static func picker(onPick: @escaping @MainActor (_ roomId: String) -> Void) -> QuickSwitcherActions {
        QuickSwitcherActions(
            mode: .pickRoom,
            searchPeople: { _ in [] },
            openRoom: nil,
            startDirectChat: nil,
            openRoomInNewWindow: nil,
            pickRoom: onPick
        )
    }

    /// The work for a decision, or `nil` if this switcher does nothing for
    /// it (an ignored row, or a hook the app has not wired yet).
    @MainActor
    func handler(for decision: QuickSwitcherDecision) -> (@MainActor () async throws -> Void)? {
        switch decision {
        case let .openRoom(roomId):
            guard let openRoom else { return nil }
            return { try await openRoom(roomId) }
        case let .openRoomInNewWindow(roomId):
            guard let openRoomInNewWindow else { return nil }
            return { try await openRoomInNewWindow(roomId) }
        case let .startDirectChat(userId):
            guard let startDirectChat else { return nil }
            return { try await startDirectChat(userId) }
        case let .pickRoom(roomId):
            guard let pickRoom else { return nil }
            return { pickRoom(roomId) }
        case .ignore:
            return nil
        }
    }
}

/// The ⌘K quick switcher sheet (MATRIX-114, D-7a): a search field over a
/// list of rooms, then people from the user directory.
///
/// Arrow keys move the selection, Return opens it, ⌥-Return is reserved for
/// a new window (MATRIX-116), and Esc closes the sheet. Room results are
/// local and show at once; directory results add below them when the
/// debounced search returns. The ranking and merge rules live in
/// `Models.QuickSwitcherRanking`.
public struct QuickSwitcherView: View {
    static let startErrorMessage = "Something went wrong while trying to open this chat."
    /// The pause after the last keystroke before the directory is searched.
    static let searchDebounce: Duration = .milliseconds(250)

    let rooms: [QuickSwitcherRoom]
    let currentRoomId: String?
    let ownUserId: String?
    let imageLoader: ImageLoader?
    let actions: QuickSwitcherActions

    @State var query: String
    /// Directory results for the latest settled query, in server order.
    @State var directoryResults: [NewChatPerson]
    /// The keyboard selection, which Return acts on.
    @State var highlightedId: String?
    /// The row under the pointer. Visual only.
    @State var hoveredId: String?
    @State var isSearching = false
    @State var isBusy = false
    @State var errorMessage: String?
    @FocusState var isFieldFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - rooms: every room to offer, from `QuickSwitcherRoomDirectory`.
    ///   - currentRoomId: the room the window shows; listed last when the
    ///     query is empty.
    ///   - ownUserId: never listed as a person.
    ///   - imageLoader: loads avatars.
    ///   - actions: `navigate(...)` or `picker(onPick:)`.
    ///   - query: the starting text. Snapshot tests set it.
    ///   - directoryResults: the starting directory results. Snapshot tests
    ///     set them.
    public init(
        rooms: [QuickSwitcherRoom],
        currentRoomId: String?,
        ownUserId: String?,
        imageLoader: ImageLoader?,
        actions: QuickSwitcherActions,
        query: String = "",
        directoryResults: [NewChatPerson] = []
    ) {
        self.rooms = rooms
        self.currentRoomId = currentRoomId
        self.ownUserId = ownUserId
        self.imageLoader = imageLoader
        self.actions = actions
        self._query = State(initialValue: query)
        self._directoryResults = State(initialValue: directoryResults)
    }

    // MARK: - Derived state

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var results: [QuickSwitcherResult] {
        let ranked = QuickSwitcherRanking.rankRooms(rooms, query: trimmedQuery, currentRoomId: currentRoomId)
        return QuickSwitcherRanking.merge(
            rankedRooms: ranked,
            query: trimmedQuery,
            directoryResults: directoryResults,
            ownUserId: ownUserId,
            mode: actions.mode
        )
    }

    /// The row Return acts on: the arrowed row if it is still listed, else
    /// the first row.
    func effectiveHighlightId(in results: [QuickSwitcherResult]) -> String? {
        if let highlightedId, results.contains(where: { $0.id == highlightedId }) {
            return highlightedId
        }
        return results.first?.id
    }

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            resultList
            if let errorMessage {
                Divider()
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .frame(width: 560, height: 420)
        .onAppear { isFieldFocused = true }
        .onChange(of: query) { _, _ in highlightedId = nil }
        .task(id: trimmedQuery) { await runSearch() }
        #if os(macOS)
            .onExitCommand(perform: close)
        #endif
    }

    var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isFieldFocused)
                .onSubmit { activateHighlighted(key: Self.submitKey) }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }
            if isSearching || isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
    }

    var placeholder: String {
        switch actions.mode {
        case .navigate: "Jump to a room or person"
        case .pickRoom: "Choose a room"
        }
    }

    var resultList: some View {
        let results = results
        let highlight = effectiveHighlightId(in: results)
        let roomResults = results.filter(\.isRoom)
        let personResults = results.filter { !$0.isRoom }

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if !roomResults.isEmpty {
                        sectionLabel(trimmedQuery.isEmpty ? "Recent" : "Rooms")
                        rows(roomResults, highlight: highlight)
                    }
                    if !personResults.isEmpty {
                        sectionLabel("People")
                        rows(personResults, highlight: highlight)
                    }
                    if results.isEmpty, !trimmedQuery.isEmpty, !isSearching {
                        Text("No matches")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                }
                .padding(8)
            }
            .onChange(of: highlightedId) { _, id in
                guard let id else { return }
                proxy.scrollTo(id)
            }
        }
    }

    func sectionLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    func rows(_ results: [QuickSwitcherResult], highlight: String?) -> some View {
        ForEach(results) { result in
            Button {
                activate(result, key: .primary)
            } label: {
                let isHighlighted = result.id == highlight || result.id == hoveredId
                switch result {
                case let .room(room):
                    QuickSwitcherRoomRow(room: room, imageLoader: imageLoader, isHighlighted: isHighlighted)
                case let .person(person):
                    NewChatPersonRow(person: person, imageLoader: imageLoader, isHighlighted: isHighlighted)
                }
            }
            .buttonStyle(.plain)
            .id(result.id)
            .onHover { hovering in
                if hovering {
                    hoveredId = result.id
                } else if hoveredId == result.id {
                    hoveredId = nil
                }
            }
        }
    }
}

// MARK: - Behavior

extension QuickSwitcherView {
    /// The key Return was pressed with. A text field's submit carries no
    /// modifiers, so the Mac reads them from the current event.
    static var submitKey: QuickSwitcherActivationKey {
        #if os(macOS)
            NSEvent.modifierFlags.contains(.option) ? .alternate : .primary
        #else
            .primary
        #endif
    }

    func close() {
        dismiss()
    }

    func moveHighlight(by offset: Int) -> KeyPress.Result {
        let results = results
        guard !results.isEmpty else { return .ignored }

        let current = effectiveHighlightId(in: results).flatMap { id in results.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + offset, 0), results.count - 1) } ?? 0
        highlightedId = results[next].id
        return .handled
    }

    func activateHighlighted(key: QuickSwitcherActivationKey) {
        let results = results
        guard let id = effectiveHighlightId(in: results), let result = results.first(where: { $0.id == id }) else { return }
        activate(result, key: key)
    }

    /// Runs the decision for a row and closes the sheet when it succeeds. A
    /// decision the app has no handler for does nothing, and the sheet stays.
    func activate(_ result: QuickSwitcherResult, key: QuickSwitcherActivationKey) {
        guard !isBusy else { return }
        let decision = QuickSwitcherRanking.decide(result, mode: actions.mode, key: key)
        guard let handler = actions.handler(for: decision) else { return }

        isBusy = true
        errorMessage = nil
        Task {
            defer { isBusy = false }
            do {
                try await handler()
                close()
            } catch {
                Logger.viewCycle.error("quick switcher: \(String(describing: decision)) failed: \(error)")
                errorMessage = Self.startErrorMessage
            }
        }
    }

    /// Debounced directory search for the current query.
    ///
    /// Runs as a `.task(id:)`, so a new keystroke cancels the previous
    /// search. Room results never wait for this.
    func runSearch() async {
        let query = trimmedQuery
        guard QuickSwitcherRanking.shouldSearchDirectory(query: query, mode: actions.mode) else {
            isSearching = false
            directoryResults = []
            return
        }

        isSearching = true
        do {
            try await Task.sleep(for: Self.searchDebounce)
        } catch {
            return
        }

        do {
            let people = try await actions.searchPeople(query)
            guard !Task.isCancelled else { return }
            directoryResults = people
        } catch is CancellationError {
            return
        } catch {
            Logger.viewCycle.error("quick switcher: user search failed: \(error)")
        }
        isSearching = false
    }
}

// MARK: - Room row

/// A room in the switcher: avatar, name, and the alias when there is one.
/// Same size and highlight as `NewChatPersonRow`, so rooms and people line
/// up.
struct QuickSwitcherRoomRow: View {
    let room: QuickSwitcherRoom
    let imageLoader: ImageLoader?
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            ChatListAvatar(
                model: ChatListRowModel(id: room.id, title: room.name, avatarUrl: room.avatarUrl, isDirect: room.isDirect),
                size: 24,
                imageLoader: imageLoader
            )
            Text(room.name)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            if let secondary = room.detail ?? room.canonicalAlias {
                Text(secondary)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.primary.opacity(0.08) : Color.clear)
        )
    }
}

#Preview {
    QuickSwitcherView(
        rooms: [
            QuickSwitcherRoom(id: "!a", name: "General", canonicalAlias: "#general:example.org", recencyRank: 0),
            QuickSwitcherRoom(id: "!b", name: "Alice", isDirect: true, directUserId: "@alice:example.org", recencyRank: 1),
        ],
        currentRoomId: nil,
        ownUserId: "@me:example.org",
        imageLoader: nil,
        actions: .picker { _ in }
    )
}
