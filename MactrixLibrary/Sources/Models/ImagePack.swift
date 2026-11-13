import Foundation

/// One custom emoji of an image pack (MATRIX-155).
public struct ImagePackEmoji: Codable, Hashable, Identifiable, Sendable {
    /// The name without colons, for example "party_parrot".
    public let shortcode: String
    /// The image, an `mxc://` URI. A reaction with this emoji sends the URI
    /// as its key.
    public let url: String

    public var id: String {
        shortcode
    }

    public init(shortcode: String, url: String) {
        self.shortcode = shortcode
        self.url = url
    }
}

/// The custom emoji of one MSC2545 image pack (MATRIX-155).
///
/// The mautrix-slack bridge writes the emoji of a Slack workspace as
/// `m.room.image_pack` state events into the workspace's space room
/// (`docs/research/slack-custom-emoji.md`, A4). `parse(roomState:)` reads
/// them from the room state. The type is display data only: the reaction
/// picker lists the emoji, and a pick sends the emoji's URI through the SDK.
///
/// Usage:
/// ```swift
/// let packs = try ImagePack.parse(roomState: data)
/// let matches = packs[0].search("parrot")
/// ```
public struct ImagePack: Codable, Equatable, Identifiable, Sendable {
    /// The event type of a pack in a room's state.
    public static let eventType = "m.room.image_pack"

    /// The pack's state key. For a pack that the bridge split into parts, the
    /// key that the parts share.
    public let key: String
    /// The pack's name, or nil when the pack has none.
    public let displayName: String?
    /// The emoji, sorted by shortcode.
    public let emoji: [ImagePackEmoji]

    public var id: String {
        key
    }

    public init(key: String, displayName: String?, emoji: [ImagePackEmoji]) {
        self.key = key
        self.displayName = displayName
        self.emoji = emoji
    }

    /// Whether a reaction key is an image (an `mxc://` URI), not a Unicode
    /// emoji.
    public static func isImageKey(_ key: String) -> Bool {
        key.hasPrefix("mxc://")
    }

    /// The pack with `name` as its display name, if it has none.
    public func named(fallback name: String?) -> ImagePack {
        guard displayName == nil, let name, !name.isEmpty else { return self }
        return ImagePack(key: key, displayName: name, emoji: emoji)
    }

    // MARK: - Search

    /// The emoji whose shortcode contains `query`, in shortcode order, with
    /// the shortcodes that start with the query first. Case does not matter,
    /// and colons around the query are ignored (":parrot:").
    ///
    /// - Parameter query: The search text. Blank text matches nothing.
    public func search(_ query: String) -> [ImagePackEmoji] {
        searchIndices(query).map { emoji[$0] }
    }

    /// `search(_:)` as indices into `emoji`.
    func searchIndices(_ query: String) -> [Int] {
        let needle = query.lowercased().trimmingCharacters(in: Self.queryPadding)
        guard !needle.isEmpty else { return [] }
        var prefixMatches: [Int] = []
        var otherMatches: [Int] = []
        for (index, item) in emoji.enumerated() {
            let shortcode = item.shortcode.lowercased()
            if shortcode.hasPrefix(needle) {
                prefixMatches.append(index)
            } else if shortcode.contains(needle) {
                otherMatches.append(index)
            }
        }
        return prefixMatches + otherMatches
    }

    private static let queryPadding = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":"))
}

// MARK: - Parsing

public extension ImagePack {
    /// The room state is not a JSON array of events.
    struct MalformedRoomState: Error, Equatable {
        public init() {}
    }

    /// Reads the emoji packs from the JSON array that
    /// `GET /_matrix/client/v3/rooms/{roomId}/state` returns.
    ///
    /// Rules:
    /// - Only `m.room.image_pack` events count. Their content is the MSC2545
    ///   shape: `images: {shortcode: {url}}` and `pack: {display_name, usage}`.
    /// - mautrix splits a pack over 62 KB into parts: state keys `<key>`,
    ///   `<key>.001`, and so on, each with `fi.mau.combined_pack_key`,
    ///   `fi.mau.combined_pack_index`, and `fi.mau.combined_pack_count`, and
    ///   the display name `<name> (part N)`. The parts of one key join into
    ///   one pack, in index order, and the name loses its part suffix. A part
    ///   whose index is not below the count of the first part is from an
    ///   older, larger import and is dropped. If the event with the state key
    ///   `<key>` is not a part, it is the newest import and every part is
    ///   dropped.
    /// - An image without an `mxc://` URL is dropped. So is an image, or a
    ///   pack, whose `usage` list does not have `emoticon` (a sticker). A
    ///   shortcode that occurs twice keeps its first image.
    /// - A pack with no emoji is left out. The packs are sorted by key and
    ///   the emoji by shortcode.
    ///
    /// - Parameter data: The response body.
    /// - Returns: The packs. Empty when the room has none.
    /// - Throws: `MalformedRoomState` when the body is not an array of events.
    static func parse(roomState data: Data) throws -> [ImagePack] {
        guard let events = try? JSONDecoder().decode([StateEvent].self, from: data) else {
            throw MalformedRoomState()
        }
        var groups: [String: [PackPart]] = [:]
        for event in events {
            guard event.type == eventType, let stateKey = event.stateKey, let content = event.content else { continue }
            let part = PackPart(stateKey: stateKey, content: content)
            groups[content.combinedKey ?? stateKey, default: []].append(part)
        }
        return groups
            .compactMap { key, parts in pack(key: key, parts: parts) }
            .sorted { $0.key < $1.key }
    }

    private static func pack(key: String, parts: [PackPart]) -> ImagePack? {
        let ordered = currentParts(key: key, parts: parts)
        var urls: [String: String] = [:]
        for part in ordered where part.content.allowsEmoticons {
            for (shortcode, image) in part.content.images {
                guard let url = image.url, isImageKey(url), image.allowsEmoticon, urls[shortcode] == nil else { continue }
                urls[shortcode] = url
            }
        }
        guard !urls.isEmpty else { return nil }
        let emoji = urls
            .map { ImagePackEmoji(shortcode: $0.key, url: $0.value) }
            .sorted { ($0.shortcode.lowercased(), $0.shortcode) < ($1.shortcode.lowercased(), $1.shortcode) }
        let name = ordered.lazy.compactMap(\.content.displayName).first.map(withoutPartSuffix)
        return ImagePack(key: key, displayName: name, emoji: emoji)
    }

    /// The parts of the newest import, in index order.
    private static func currentParts(key: String, parts: [PackPart]) -> [PackPart] {
        if let whole = parts.first(where: { $0.stateKey == key && $0.content.combinedKey == nil }) {
            return [whole]
        }
        let ordered = parts.sorted { ($0.index, $0.stateKey) < ($1.index, $1.stateKey) }
        guard let count = ordered.first(where: { $0.stateKey == key })?.content.combinedCount, count > 0 else {
            return ordered
        }
        return ordered.filter { $0.index < count }
    }

    /// "Acme emojis (part 2)" to "Acme emojis".
    private static func withoutPartSuffix(_ name: String) -> String {
        guard name.hasSuffix(")"), let range = name.range(of: " (part ", options: .backwards) else { return name }
        let number = name[range.upperBound...].dropLast()
        guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return name }
        return String(name[..<range.lowerBound])
    }
}

private struct PackPart {
    let stateKey: String
    let content: PackContent

    var index: Int {
        content.combinedIndex ?? 0
    }
}

/// One event of the room state. Only a pack event keeps its content, so the
/// content of every other event type is never decoded.
private struct StateEvent: Decodable {
    let type: String
    let stateKey: String?
    let content: PackContent?

    private enum CodingKeys: String, CodingKey {
        case type
        case stateKey = "state_key"
        case content
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        stateKey = try? container.decode(String.self, forKey: .stateKey)
        content = type == ImagePack.eventType ? try? container.decode(PackContent.self, forKey: .content) : nil
    }
}

/// One image of a pack. A field that does not fit reads as absent.
private struct PackImage: Decodable {
    let url: String?
    let usage: [String]?

    private enum CodingKeys: String, CodingKey {
        case url
        case usage
    }

    init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        url = try? container?.decode(String.self, forKey: .url)
        usage = try? container?.decode([String].self, forKey: .usage)
    }

    var allowsEmoticon: Bool {
        PackContent.allowsEmoticons(usage)
    }
}

private struct PackMetadata: Decodable {
    let displayName: String?
    let usage: [String]?

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case usage
    }

    init(from decoder: Decoder) {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        displayName = try? container?.decode(String.self, forKey: .displayName)
        usage = try? container?.decode([String].self, forKey: .usage)
    }
}

/// The content of an `m.room.image_pack` event. Each field that does not fit
/// reads as absent, so one bad field does not lose the pack.
private struct PackContent: Decodable {
    /// MSC2545: no usage list, or an empty one, means every usage.
    static func allowsEmoticons(_ usage: [String]?) -> Bool {
        guard let usage, !usage.isEmpty else { return true }
        return usage.contains("emoticon")
    }

    let images: [String: PackImage]
    let displayName: String?
    let allowsEmoticons: Bool
    let combinedKey: String?
    let combinedIndex: Int?
    let combinedCount: Int?

    private enum CodingKeys: String, CodingKey {
        case images
        case pack
        case combinedKey = "fi.mau.combined_pack_key"
        case combinedIndex = "fi.mau.combined_pack_index"
        case combinedCount = "fi.mau.combined_pack_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        images = (try? container.decode([String: PackImage].self, forKey: .images)) ?? [:]
        let metadata = try? container.decode(PackMetadata.self, forKey: .pack)
        let name = metadata?.displayName
        displayName = name.flatMap { $0.isEmpty ? nil : $0 }
        allowsEmoticons = Self.allowsEmoticons(metadata?.usage)
        combinedKey = try? container.decode(String.self, forKey: .combinedKey)
        combinedIndex = try? container.decode(Int.self, forKey: .combinedIndex)
        combinedCount = try? container.decode(Int.self, forKey: .combinedCount)
    }
}
