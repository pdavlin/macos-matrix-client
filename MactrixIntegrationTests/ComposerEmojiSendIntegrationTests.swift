import Core
import Foundation
@testable import Mactrix
import MatrixRustSDK
import Models
import XCTest

/// Network integration test for MATRIX-156 (research unknown 7): does the
/// pinned SDK's `messageEventContentFromMarkdown` keep an emoticon `<img>`
/// tag in `formatted_body`, and what does it put into the plain `body`?
///
/// With the dev account only, the test:
///
///   1. Signs in with a password, as `LoginIntegrationTests` does (no
///      keychain, see that file).
///   2. Finds the joined room named "mactrix-integration-scratch", or
///      creates it: private, not encrypted, no other member.
///   3. Sends one message whose markdown comes from the composer's send path
///      (`ComposerEmojiMarkup.resolving`), with a made-up `mxc://` URL.
///   4. Reads the remote echo from the room's timeline and checks the two
///      bodies, in the event as the homeserver has it (the SDK's
///      `debugInfo().originalJson`) and in the timeline item.
///   5. Signs out.
///
/// Result on 2026-11-16 with the pinned SDK 26.04.01 (the same flow, run
/// from a command-line runner without the app as test host):
/// - The event's `formatted_body` holds the tag as sent, with
///   `data-mx-emoticon`. The line after a tag alone on its line keeps its
///   markdown.
/// - The event's `body` is the markdown source, with the tags.
/// - The timeline item's formatted body is sanitized by the SDK: the `<img>`
///   keeps `src`, `alt`, `title`, and `height`, and loses `data-mx-emoticon`.
///
/// The test bundle has the Mactrix app as its host. A run starts that app,
/// which restores the signed-in session of this Mac. Run it only where that
/// is acceptable.
///
/// It is skipped unless `MATRIX_DEV_USER` and `MATRIX_DEV_PASSWORD` are set
/// (`LoginIntegrationTests` describes how to give them). Never run it
/// against the prod account (CLAUDE.md hard rule 3).
final class ComposerEmojiSendIntegrationTests: XCTestCase {
    private static let deviceName = "s156-integration"
    private static let homeserver = "davlin.io"
    private static let scratchRoomName = "mactrix-integration-scratch"
    private static let shortcode = "mactrix_scratch"
    private static let emojiURL = "mxc://davlin.io/mactrixIntegrationScratchEmoji"

    /// Collects every event the timeline reports. The test only searches
    /// them, so it does not keep the list order.
    private final class EventCollector: TimelineListener, @unchecked Sendable {
        private let lock = NSLock()
        private var events: [MatrixRustSDK.EventTimelineItem] = []

        func onUpdate(diff: [TimelineDiff]) {
            var items: [TimelineItem] = []
            for change in diff {
                switch change {
                case let .append(values), let .reset(values):
                    items += values
                case let .pushFront(value), let .pushBack(value):
                    items.append(value)
                case let .insert(_, value), let .set(_, value):
                    items.append(value)
                case .clear, .popFront, .popBack, .remove, .truncate:
                    break
                }
            }
            let found = items.compactMap { $0.asEvent() }
            lock.withLock { events += found }
        }

        /// The newest remote text event whose body has `marker`, with its
        /// text content.
        func remoteText(containing marker: String) -> (event: MatrixRustSDK.EventTimelineItem, text: TextMessageContent)? {
            lock.withLock {
                for event in events.reversed() where event.isRemote {
                    guard case let .msgLike(content: msgLike) = event.content,
                          case let .message(message) = msgLike.kind,
                          case let .text(text) = message.msgType,
                          text.body.contains(marker)
                    else { continue }
                    return (event, text)
                }
                return nil
            }
        }
    }

    func testMarkdownSendKeepsTheEmoticonTag() async throws {
        let env = ProcessInfo.processInfo.environment
        guard
            let devUserId = env["MATRIX_DEV_USER"] ?? env["TEST_RUNNER_MATRIX_DEV_USER"],
            let devPassword = env["MATRIX_DEV_PASSWORD"] ?? env["TEST_RUNNER_MATRIX_DEV_PASSWORD"],
            !devPassword.isEmpty
        else {
            throw XCTSkip("MATRIX_DEV_PASSWORD not set — skipping network integration test.")
        }

        let homeserverLogin = try await MatrixClient.loginDetails(homeServer: Self.homeserver)
        let client = homeserverLogin.unauthenticatedClient
        try await client.login(
            username: devUserId,
            password: devPassword,
            initialDeviceName: Self.deviceName,
            deviceId: nil
        )
        // Only the dev account from the environment sends anything.
        guard try client.userId() == devUserId else {
            try await client.logout()
            XCTFail("signed in as an account that is not MATRIX_DEV_USER")
            return
        }

        let syncService = try await client.syncService().finish()
        await syncService.start()
        do {
            try await sendAndCheck(client: client)
        } catch {
            await syncService.stop()
            try? await client.logout()
            throw error
        }
        await syncService.stop()
        try await client.logout()
    }

    private func sendAndCheck(client: ClientProtocol) async throws {
        let room = try await scratchRoom(client: client)
        let timeline = try await room.timeline()
        let collector = EventCollector()
        let handle = await timeline.addListener(listener: collector)
        defer { handle.cancel() }

        // The composer's send path: the token alone on a line (the tag then
        // has a line break before its end), and a token in a line with bold
        // text.
        let marker = "s156-\(UUID().uuidString)"
        let pack = ImagePack(key: "integration", displayName: nil, emoji: [
            ImagePackEmoji(shortcode: Self.shortcode, url: Self.emojiURL),
        ])
        let draft = ":\(Self.shortcode):\n**bold** :\(Self.shortcode): \(marker)"
        let outgoing = MentionMarkdown.outgoingMessage(fromDraftText: draft).resolvingEmoji(in: [pack])
        XCTAssertNotEqual(outgoing.markdown, draft, "the send path did not resolve the token")

        _ = try await timeline.send(msg: messageEventContentFromMarkdown(md: outgoing.markdown))

        var sent: (event: MatrixRustSDK.EventTimelineItem, text: TextMessageContent)?
        for _ in 0 ..< 120 {
            sent = collector.remoteText(containing: marker)
            if sent != nil { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        let echo = try XCTUnwrap(sent, "the remote echo did not arrive in 30 seconds")

        // The event as the homeserver has it.
        let json = try XCTUnwrap(echo.event.lazyProvider.debugInfo().originalJson, "the event has no original JSON")
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        let content = try XCTUnwrap(object?["content"] as? [String: Any], "the event has no content")
        let wireBody = try XCTUnwrap(content["body"] as? String)
        let wireFormatted = try XCTUnwrap(content["formatted_body"] as? String, "the event has no formatted_body")

        // Unknown 7: the tag reaches formatted_body as sent.
        XCTAssertEqual(content["format"] as? String, "org.matrix.custom.html")
        let tagStart = "<img data-mx-emoticon src=\"\(Self.emojiURL)\" alt=\":\(Self.shortcode):\""
        XCTAssertEqual(wireFormatted.components(separatedBy: tagStart).count - 1, 2, "formatted_body: \(wireFormatted)")
        // The tag alone on the first line did not start an HTML block: the
        // second line kept its markdown.
        XCTAssertTrue(wireFormatted.contains("<strong>bold</strong>"), "formatted_body: \(wireFormatted)")
        // The plain body is the markdown source, with the tags.
        XCTAssertEqual(wireBody, outgoing.markdown)

        // The timeline item: the same plain body, which the app reads
        // through `displayBody`, and a sanitized formatted body that keeps
        // the two images and their source.
        XCTAssertEqual(echo.text.body, outgoing.markdown)
        XCTAssertEqual(echo.text.displayBody, draft)
        let formatted = try XCTUnwrap(echo.text.formatted, "the timeline item has no formatted body")
        XCTAssertEqual(formatted.format, .html)
        XCTAssertEqual(
            formatted.body.components(separatedBy: "src=\"\(Self.emojiURL)\"").count - 1, 2,
            "timeline formatted body: \(formatted.body)"
        )
    }

    /// The joined scratch room, or a new one. The room list of a new sign-in
    /// fills from the sync, so the search waits for it.
    private func scratchRoom(client: ClientProtocol) async throws -> MatrixRustSDK.Room {
        for _ in 0 ..< 40 {
            let found = client.rooms().first {
                $0.membership() == .joined && $0.displayName() == Self.scratchRoomName
            }
            if let found { return found }
            try await Task.sleep(for: .milliseconds(250))
        }
        let parameters = CreateRoomParameters(
            name: Self.scratchRoomName, isEncrypted: false, isDirect: false, visibility: .private,
            preset: .privateChat, invite: []
        )
        let roomId = try await client.createRoom(request: parameters)
        return try await withThrowingTaskGroup(of: MatrixRustSDK.Room.self) { group in
            group.addTask { try await client.awaitRoomRemoteEcho(roomId: roomId) }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw CancellationError()
            }
            defer { group.cancelAll() }
            guard let room = try await group.next() else { throw CancellationError() }
            return room
        }
    }
}
