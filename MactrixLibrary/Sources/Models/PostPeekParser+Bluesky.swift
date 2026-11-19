import Foundation

/// The Bluesky half of `PostPeekParser` (MATRIX-201): the JSON of
/// `app.bsky.feed.getPostThread`. The rules come from post-peek
/// (https://github.com/tsvb/post-peek, MIT), re-implemented here.
extension PostPeekParser {
    static let sensitiveLabels: Set = ["porn", "sexual", "nudity", "graphic-media", "gore"]

    /// The post of a Bluesky `getPostThread` answer with HTTP status 200.
    public static func blueskyPost(from data: Data) throws -> PeekPost {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), let thread = json["thread"] else {
            throw PostPeekFailure.badResponse
        }
        if thread["$type"]?.string == "app.bsky.feed.defs#notFoundPost" {
            throw PostPeekFailure.notFound
        }
        // A blocked post, or a shape this parser does not know.
        guard let postJSON = thread["post"], postJSON.object != nil else { throw PostPeekFailure.unavailable }
        if let withheld = blueskyWithheld(postJSON) {
            throw withheld
        }
        guard var post = blueskyPost(postJSON, record: postJSON["record"], embed: postJSON["embed"], nested: false) else {
            throw PostPeekFailure.badResponse
        }
        if let parentURI = postJSON["record"]?["reply"]?["parent"]?["uri"]?.string {
            let parent = thread["parent"]?["post"]
            let label = parent.flatMap { blueskyWithheld($0) == nil ? $0["author"].flatMap(blueskyHandle) : nil }
            post.replyTo = PeekReplyContext(
                link: PostPeekLink(atURI: parentURI),
                label: label.map { "@\($0)" } ?? "a post"
            )
        }
        return post
    }

    /// The failure that withholds `post`, or nil.
    static func blueskyWithheld(_ post: JSONValue) -> PostPeekFailure? {
        let author = post["author"]
        let authorLabels = author?["labels"]?.array ?? []
        if authorLabels.contains(where: { $0["val"]?.string == "!no-unauthenticated" }) {
            return .loggedInOnly
        }
        if (post["labels"]?.array ?? []).contains(where: { $0["val"]?.string == "!hide" }) {
            return .hiddenByModerators
        }
        let did = author?["did"]?.string
        if authorLabels.contains(where: { $0["val"]?.string == "!hide" && $0["uri"]?.string == did }) {
            return .hiddenByModerators
        }
        return nil
    }

    private static func blueskyPost(_ view: JSONValue, record: JSONValue?, embed: JSONValue?, nested: Bool) -> PeekPost? {
        guard let uri = view["uri"]?.string, case let .bluesky(_, rkey)? = PostPeekLink(atURI: uri),
              let authorJSON = view["author"], let handle = blueskyHandle(authorJSON),
              let url = URL(string: "https://bsky.app/profile/\(handle)/post/\(rkey)")
        else { return nil }

        // The labels on the post, and on the account (with the DID as the
        // subject). A label on the profile record covers only the avatar.
        let did = authorJSON["did"]?.string
        let authorLabels = authorJSON["labels"]?.array ?? []
        let labels = ((view["labels"]?.array ?? []) + authorLabels.filter { $0["uri"]?.string == did }).compactMap { $0["val"]?.string }
        let hidesAvatar = authorLabels.contains { sensitiveLabels.contains($0["val"]?.string ?? "") }

        let author = PeekAuthor(
            name: authorJSON["displayName"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? handle,
            handle: handle,
            avatarURL: hidesAvatar ? nil : mediaURL(authorJSON["avatar"]?.string, hosts: blueskyMediaHosts),
            profileURL: URL(string: "https://bsky.app/profile/\(handle)"),
            isVerified: authorJSON["verification"]?["verifiedStatus"]?.string == "valid"
        )
        var post = PeekPost(
            link: .bluesky(actor: did ?? handle, rkey: rkey),
            url: url,
            author: author,
            text: blueskyText(record?["text"]?.string ?? "", facets: record?["facets"]?.array ?? []),
            date: date(record?["createdAt"]?.string),
            mediaWarning: labels.first { sensitiveLabels.contains($0) },
            hasContentWarning: labels.contains("!warn")
        )
        blueskyMedia(embed, into: &post)
        guard !nested else { return post }

        switch embed?["$type"]?.string {
        case "app.bsky.embed.external#view":
            post.card = blueskyCard(embed?["external"])
        case "app.bsky.embed.record#view":
            post.quote = blueskyQuote(embed?["record"])
        case "app.bsky.embed.recordWithMedia#view":
            post.quote = blueskyQuote(embed?["record"]?["record"])
        default:
            break
        }
        return post
    }

    private static func blueskyMedia(_ embed: JSONValue?, into post: inout PeekPost) {
        switch embed?["$type"]?.string {
        case "app.bsky.embed.images#view":
            let images = embed?["images"]?.array ?? []
            post.photos = images.compactMap { image in
                let source = images.count == 1 ? image["fullsize"]?.string : image["thumb"]?.string
                guard let url = mediaURL(source, hosts: blueskyMediaHosts) else { return nil }
                return PeekPhoto(
                    url: url,
                    alt: image["alt"]?.string ?? "",
                    aspectRatio: ratio(image["aspectRatio"]?["width"]?.number, image["aspectRatio"]?["height"]?.number)
                )
            }
        case "app.bsky.embed.video#view":
            guard let embed, let playlist = mediaURL(embed["playlist"]?.string, hosts: blueskyMediaHosts) else { return }
            post.videos = [PeekVideo(
                url: playlist,
                posterURL: mediaURL(embed["thumbnail"]?.string, hosts: blueskyMediaHosts),
                aspectRatio: ratio(embed["aspectRatio"]?["width"]?.number, embed["aspectRatio"]?["height"]?.number),
                isGIF: embed["presentation"]?.string == "gif"
            )]
        case "app.bsky.embed.recordWithMedia#view":
            blueskyMedia(embed?["media"], into: &post)
        default:
            break
        }
    }

    private static func blueskyCard(_ external: JSONValue?) -> PeekCard? {
        guard let external, let url = webURL(external["uri"]?.string) else { return nil }
        let title = external["title"]?.string.flatMap { $0.isEmpty ? nil : $0 } ?? url.absoluteString
        return PeekCard(
            url: url,
            title: title,
            description: external["description"]?.string.flatMap { $0.isEmpty ? nil : $0 },
            imageURL: mediaURL(external["thumb"]?.string, hosts: blueskyMediaHosts),
            domain: url.host ?? ""
        )
    }

    private static func blueskyQuote(_ record: JSONValue?) -> PeekQuote? {
        guard let record, let type = record["$type"]?.string else { return nil }
        guard type == "app.bsky.embed.record#viewRecord" else {
            let gone = ["#viewNotFound", "#viewBlocked", "#viewDetached"].contains { type.hasSuffix($0) }
            return gone ? .unavailable : nil
        }
        // A feed, a list or a starter pack is not a post.
        guard record["value"]?["$type"]?.string == "app.bsky.feed.post" else { return nil }
        if blueskyWithheld(record) != nil {
            return .unavailable
        }
        let post = blueskyPost(record, record: record["value"], embed: record["embeds"]?.array.first, nested: true)
        return post.map(PeekQuote.post) ?? .unavailable
    }

    private static func blueskyHandle(_ author: JSONValue) -> String? {
        if let handle = author["handle"]?.string, !handle.isEmpty, handle != "handle.invalid" {
            return handle
        }
        return author["did"]?.string
    }

    /// The text cut at its facets. Facets index UTF-8 bytes.
    private static func blueskyText(_ text: String, facets: [JSONValue]) -> [PeekTextRun] {
        let bytes = Array(text.utf8)
        let sorted = facets.sorted { ($0["index"]?["byteStart"]?.number ?? 0) < ($1["index"]?["byteStart"]?.number ?? 0) }
        var runs: [PeekTextRun] = []
        var position = 0
        func string(_ from: Int, _ to: Int) -> String {
            // Decoding repairs a facet that cuts a character in two, where
            // `String(bytes:encoding:)` would drop the whole run.
            // swiftlint:disable:next optional_data_string_conversion
            String(decoding: bytes[from ..< to], as: UTF8.self)
        }
        for facet in sorted {
            guard let start = facet["index"]?["byteStart"]?.number.map(Int.init),
                  let end = facet["index"]?["byteEnd"]?.number.map(Int.init),
                  start >= position, end > start, end <= bytes.count
            else { continue }
            let feature = facet["features"]?.array.first
            let link: URL? = switch feature?["$type"]?.string {
            case "app.bsky.richtext.facet#link":
                webURL(feature?["uri"]?.string)
            case "app.bsky.richtext.facet#mention":
                feature?["did"]?.string.flatMap { URL(string: "https://bsky.app/profile/\($0)") }
            case "app.bsky.richtext.facet#tag":
                feature?["tag"]?.string.flatMap { URL(string: "https://bsky.app/hashtag/\(queryEncoded($0))") }
            default:
                nil
            }
            guard let link else { continue }
            if start > position {
                runs.append(PeekTextRun(string(position, start)))
            }
            let label = string(start, end)
            runs.append(PeekTextRun(label, link: link))
            // The author picks the link text. Where it names one site and
            // the link opens another, say where it goes, as bsky.app does.
            let isLink = feature?["$type"]?.string == "app.bsky.richtext.facet#link"
            if isLink, let named = namedHost(label), let real = link.host.map(withoutWWW), named != real {
                runs.append(PeekTextRun(" (opens \(real))"))
            }
            position = end
        }
        if position < bytes.count {
            runs.append(PeekTextRun(string(position, bytes.count)))
        }
        return runs
    }

    /// The host that link text names, if it reads as an address.
    static func namedHost(_ label: String) -> String? {
        var text = label.trimmingCharacters(in: .whitespaces)
        for suffix in ["...", "…"] where text.hasSuffix(suffix) {
            text.removeLast(suffix.count)
        }
        guard !text.contains(where: \.isWhitespace), text.contains(".") else { return nil }
        let lowered = text.lowercased()
        let absolute = lowered.hasPrefix("http://") || lowered.hasPrefix("https://") ? text : "https://\(text)"
        guard let host = URLComponents(string: absolute)?.host, !host.isEmpty else { return nil }
        return withoutWWW(host.lowercased())
    }

    private static func withoutWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
