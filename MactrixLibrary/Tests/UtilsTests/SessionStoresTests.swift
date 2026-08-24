import Foundation
import Testing
@testable import Utils

struct SessionStoresTests {
    private func makeTempParent() throws -> URL {
        let parent = FileManager.default.temporaryDirectory
            .appending(component: "SessionStoresTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        return parent
    }

    @Test func keepsTheLiveStoreAndFindsSiblings() throws {
        let parent = try makeTempParent()
        defer { try? FileManager.default.removeItem(at: parent) }

        let kept = "LIVE-STORE-ID"
        for name in [kept, "ORPHAN-A", "ORPHAN-B"] {
            try FileManager.default.createDirectory(
                at: parent.appending(component: name), withIntermediateDirectories: false
            )
        }

        let orphans = SessionStores.orphanedDirectories(in: parent, keeping: kept)

        #expect(Set(orphans.map(\.lastPathComponent)) == ["ORPHAN-A", "ORPHAN-B"])
    }

    @Test func ignoresPlainFiles() throws {
        let parent = try makeTempParent()
        defer { try? FileManager.default.removeItem(at: parent) }

        try Data("not a store".utf8).write(to: parent.appending(component: "stray-file"))

        let orphans = SessionStores.orphanedDirectories(in: parent, keeping: "LIVE-STORE-ID")

        #expect(orphans.isEmpty)
    }

    @Test func missingParentYieldsNothing() {
        let missing = FileManager.default.temporaryDirectory
            .appending(component: "SessionStoresTests-missing-\(UUID().uuidString)")

        let orphans = SessionStores.orphanedDirectories(in: missing, keeping: "LIVE-STORE-ID")

        #expect(orphans.isEmpty)
    }
}
