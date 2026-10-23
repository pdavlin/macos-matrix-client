//
//  SidebarSectionCollapsibility.swift
//  Mactrix
//
//  Created by Marquis Kurt on 17-02-2026.
//

/// A structure that describes the collapsed/expanded states of sections in the sidebar.
///
/// This is typically used in conjunction with `Section(_:isExpanded)` to allow users to expand or collapse sidebar
/// content. Each collapsible sidebar section should have a corresponding entry in this structure.
///
/// ```swift
/// @Environment(WindowState.self) var windowState
///
/// Section("Spaces", isExpanded: $windowState.sidebarSections.spaces) { ... }
/// ```
///
/// MATRIX-67 replaced the Favorites, Directs, and Rooms sections with the
/// inbox chat list, which does not collapse, so only Spaces remains. Window
/// state saved before that still decodes: the decoder ignores the old keys.
///
/// > Note: You do not need to create this structure yourself. Rather, you should use the collapsibility information
/// > from ``WindowState/sidebarSections``.
struct SidebarSectionCollapsibility: Codable, Equatable {
    /// Whether the spaces section is expanded.
    var spaces = true
}
