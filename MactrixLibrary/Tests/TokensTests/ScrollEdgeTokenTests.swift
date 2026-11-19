import SwiftUI
import Testing
@testable import Tokens

/// Pins the scroll edge effect style of the sidebar (MATRIX-196).
@Suite("Scroll edge tokens")
struct ScrollEdgeTokenTests {
    @Test
    func theSidebarTopEdgeIsSoft() {
        #expect(ScrollEdgeToken.sidebarTop == .soft)
    }
}
