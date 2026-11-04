import Foundation
import Testing
@testable import Utils

/// MATRIX-89: the Sygnal `event_id_only` APNs payload.
struct PushNotificationPayloadTests {
    /// The shape Sygnal sends for an `event_id_only` pusher: the default
    /// payload plus top-level `room_id`, `event_id`, and `unread_count`.
    private let sygnalPayload: [AnyHashable: Any] = [
        "aps": [
            "mutable-content": 1,
            "alert": ["title": "Mactrix", "body": "New message"],
        ],
        "room_id": "!abc:davlin.io",
        "event_id": "$event1",
        "unread_count": 3,
    ]

    @Test func readsTheTopLevelIdentifiers() {
        #expect(PushNotificationPayload(userInfo: sygnalPayload)
            == PushNotificationPayload(roomID: "!abc:davlin.io", eventID: "$event1"))
    }

    @Test func trimsWhitespace() {
        let payload = PushNotificationPayload(userInfo: ["room_id": " !abc:davlin.io\n", "event_id": "$event1 "])
        #expect(payload == PushNotificationPayload(roomID: "!abc:davlin.io", eventID: "$event1"))
    }

    @Test func missingRoomIsRejected() {
        #expect(PushNotificationPayload(userInfo: ["event_id": "$event1"]) == nil)
    }

    @Test func missingEventIsRejected() {
        #expect(PushNotificationPayload(userInfo: ["room_id": "!abc:davlin.io"]) == nil)
    }

    @Test func emptyPayloadIsRejected() {
        #expect(PushNotificationPayload(userInfo: [:]) == nil)
    }

    @Test func nonStringValuesAreRejected() {
        #expect(PushNotificationPayload(userInfo: ["room_id": 42, "event_id": "$event1"]) == nil)
        #expect(PushNotificationPayload(userInfo: ["room_id": "!abc:davlin.io", "event_id": ["$event1"]]) == nil)
        #expect(PushNotificationPayload(userInfo: ["room_id": NSNull(), "event_id": "$event1"]) == nil)
    }

    @Test func identifiersWithoutTheSigilAreRejected() {
        #expect(PushNotificationPayload(userInfo: ["room_id": "abc:davlin.io", "event_id": "$event1"]) == nil)
        #expect(PushNotificationPayload(userInfo: ["room_id": "!abc:davlin.io", "event_id": "event1"]) == nil)
        // Swapped keys.
        #expect(PushNotificationPayload(userInfo: ["room_id": "$event1", "event_id": "!abc:davlin.io"]) == nil)
    }

    @Test func aBareSigilIsRejected() {
        #expect(PushNotificationPayload(userInfo: ["room_id": "!", "event_id": "$event1"]) == nil)
        #expect(PushNotificationPayload(userInfo: ["room_id": "!abc:davlin.io", "event_id": "  $ "]) == nil)
    }

    @Test func identifiersNestedUnderApsAreNotRead() {
        let payload: [AnyHashable: Any] = ["aps": ["room_id": "!abc:davlin.io", "event_id": "$event1"]]
        #expect(PushNotificationPayload(userInfo: payload) == nil)
    }
}

struct PusherDefaultPayloadTests {
    @Test func exactJSON() {
        // MATRIX-90 (Sygnal) must forward this payload unchanged.
        #expect(PusherDefaultPayload.json
            == #"{"aps":{"alert":{"body":"New message","title":"Mactrix"},"mutable-content":1}}"#)
    }

    @Test func parsesAsAnAPNsPayloadThatRunsTheExtension() throws {
        let object = try JSONSerialization.jsonObject(with: Data(PusherDefaultPayload.json.utf8))
        let root = try #require(object as? [String: Any])
        let aps = try #require(root["aps"] as? [String: Any])
        let alert = try #require(aps["alert"] as? [String: String])

        #expect(root.keys.sorted() == ["aps"])
        #expect(aps["mutable-content"] as? Int == 1)
        #expect(alert["title"] == NotificationDisplay.fallbackTitle)
        #expect(alert["body"] == NotificationDisplay.fallbackBody)
    }
}

struct DeviceTokenEncodingTests {
    @Test func lowercaseHexWithTwoDigitsPerByte() {
        let token = Data([0x00, 0x01, 0x0A, 0x7F, 0x80, 0xAB, 0xFF])
        #expect(DeviceTokenEncoding.hexString(token) == "00010a7f80abff")
    }

    @Test func aThirtyTwoByteTokenIsSixtyFourCharacters() {
        let token = Data((0 ..< 32).map { UInt8($0 * 7 % 256) })
        let hex = DeviceTokenEncoding.hexString(token)
        #expect(hex.count == 64)
        #expect(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    @Test func emptyTokenIsEmpty() {
        #expect(DeviceTokenEncoding.hexString(Data()).isEmpty)
    }
}

struct NotificationDisplayTests {
    private func summary(
        isDirect: Bool = false,
        body: NotificationSummary.Body = .text("hello"),
        isNoisy: Bool? = true
    ) -> NotificationSummary {
        NotificationSummary(
            roomID: "!room:davlin.io",
            roomDisplayName: "Ops",
            isDirect: isDirect,
            senderDisplayName: "Alice",
            body: body,
            isNoisy: isNoisy
        )
    }

    @Test func groupRoomShowsTheRoomAsTitleAndTheSenderAsSubtitle() {
        let display = NotificationDisplay(summary: summary())

        #expect(display == NotificationDisplay(
            title: "Ops",
            subtitle: "Alice",
            body: "hello",
            threadIdentifier: "!room:davlin.io",
            playsSound: true
        ))
    }

    @Test func directChatShowsTheSenderAsTitleAndNoSubtitle() {
        let display = NotificationDisplay(summary: summary(isDirect: true))

        #expect(display.title == "Alice")
        #expect(display.subtitle.isEmpty)
        #expect(display.body == "hello")
    }

    @Test func threadIdentifierIsTheRoom() {
        #expect(NotificationDisplay(summary: summary(isDirect: true)).threadIdentifier == "!room:davlin.io")
    }

    @Test func mediaBodies() {
        #expect(NotificationDisplay(summary: summary(body: .image)).body == "Image")
        #expect(NotificationDisplay(summary: summary(body: .video)).body == "Video")
        #expect(NotificationDisplay(summary: summary(body: .audio)).body == "Audio")
        #expect(NotificationDisplay(summary: summary(body: .file)).body == "File")
        #expect(NotificationDisplay(summary: summary(body: .sticker)).body == "Sticker")
        #expect(NotificationDisplay(summary: summary(body: .location)).body == "Location")
    }

    @Test func otherBodies() {
        #expect(NotificationDisplay(summary: summary(body: .poll)).body == "Poll")
        #expect(NotificationDisplay(summary: summary(body: .encrypted)).body == "Encrypted message")
        #expect(NotificationDisplay(summary: summary(body: .invite)).body == "Invited you")
        #expect(NotificationDisplay(summary: summary(body: .other)).body == "New message")
    }

    @Test func blankTextFallsBackToTheGenericBody() {
        #expect(NotificationDisplay(summary: summary(body: .text("  \n"))).body == "New message")
        #expect(NotificationDisplay(summary: summary(body: .text(" hi "))).body == "hi")
    }

    @Test func soundFollowsIsNoisy() {
        #expect(NotificationDisplay(summary: summary(isNoisy: true)).playsSound)
        #expect(!NotificationDisplay(summary: summary(isNoisy: false)).playsSound)
        // Unknown: the default rules decide, so play the sound.
        #expect(NotificationDisplay(summary: summary(isNoisy: nil)).playsSound)
    }
}
