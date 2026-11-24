import Core
import Models
import SwiftUI
import Tokens
import UI

/// The header above the chat list (MATRIX-226): the active filter chip when
/// the list is not the plain Inbox, else nothing.
///
/// It sits above the List, not in it and not over it, so the rows never
/// scroll under the chip's glass (CLAUDE.md hard rule 2). The chip settles
/// in from the rail side when a filter is set, and its name and color
/// change on the settle spring; under Reduce Motion both are a short fade
/// (MATRIX-225). A click on the chip shows the Inbox: the rail and the list
/// filter both.
struct SidebarFilterHeader: View {
    @Environment(AppState.self) private var appState
    @Environment(WindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The chip for a window's filters, by the rules the chat list draws
    /// with (`SidebarRail.filter`), or nil for the plain Inbox. The one
    /// source for "a chip shows": the chat list's section header reads it
    /// too, to leave out its title under the chip.
    static func activeFilter(client: MatrixClient?, windowState: WindowState) -> ChatListActiveFilter? {
        ChatListActiveFilter.chip(
            rail: SidebarRail.filter(client: client, windowState: windowState),
            list: windowState.chatListFilter,
            labels: client?.labels?.document ?? ChatLabelDocument(),
            spaceName: { id in client?.roomAccounts.topLevelSpaces.first { $0.id == id }?.name },
            paletteCount: LabelToken.palette.count
        )
    }

    var body: some View {
        if let activeFilter = Self.activeFilter(client: appState.matrixClient, windowState: windowState) {
            HStack(spacing: 0) {
                ChatListFilterChip(filter: activeFilter, usesGlass: !reduceTransparency) {
                    windowState.railFilter = .inbox
                    windowState.chatListFilter = .inbox
                }
                .animation(MotionToken.settleAnimation(reduceMotion: reduceMotion), value: activeFilter)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .padding(.bottom, 6)
            .entranceMotion(from: .leading)
        }
    }
}
