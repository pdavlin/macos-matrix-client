import Foundation
import Testing
@testable import Utils

struct MediaDownloadsTests {
    let dir = URL(filePath: "/downloads", directoryHint: .isDirectory)

    // MARK: - sanitizedFilename

    @Test func plainNamePassesThrough() {
        #expect(MediaDownloads.sanitizedFilename("photo.jpg") == "photo.jpg")
    }

    @Test func pathSeparatorsBecomeDashes() {
        #expect(MediaDownloads.sanitizedFilename("a/b/c.pdf") == "a-b-c.pdf")
        #expect(MediaDownloads.sanitizedFilename("12:30:00.png") == "12-30-00.png")
    }

    @Test func leadingDotsAreDropped() {
        #expect(MediaDownloads.sanitizedFilename(".hidden") == "hidden")
        #expect(MediaDownloads.sanitizedFilename("...doc.pdf") == "doc.pdf")
    }

    @Test func emptyAndDegenerateNamesFallBack() {
        #expect(MediaDownloads.sanitizedFilename("") == "download")
        #expect(MediaDownloads.sanitizedFilename("   ") == "download")
        #expect(MediaDownloads.sanitizedFilename("...") == "download")
    }

    // MARK: - uniqueDestination

    @Test func freshNameIsUsedDirectly() {
        let url = MediaDownloads.uniqueDestination(directory: dir, filename: "photo.jpg") { _ in false }

        #expect(url.lastPathComponent == "photo.jpg")
        #expect(url.deletingLastPathComponent().path == dir.path)
    }

    @Test func collisionAppendsCounterBeforeExtension() {
        let taken: Set = ["photo.jpg", "photo (2).jpg"]
        let url = MediaDownloads.uniqueDestination(directory: dir, filename: "photo.jpg") { candidate in
            taken.contains(candidate.lastPathComponent)
        }

        #expect(url.lastPathComponent == "photo (3).jpg")
    }

    @Test func collisionWithoutExtensionAppendsCounter() {
        let url = MediaDownloads.uniqueDestination(directory: dir, filename: "notes") { candidate in
            candidate.lastPathComponent == "notes"
        }

        #expect(url.lastPathComponent == "notes (2)")
    }

    @Test func collidingNameIsSanitizedFirst() {
        let url = MediaDownloads.uniqueDestination(directory: dir, filename: "a/b.txt") { candidate in
            candidate.lastPathComponent == "a-b.txt"
        }

        #expect(url.lastPathComponent == "a-b (2).txt")
    }
}
