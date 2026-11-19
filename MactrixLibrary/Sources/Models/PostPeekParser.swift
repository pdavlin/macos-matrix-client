import Foundation

/// Reads the JSON of X's syndication endpoint and of Bluesky's
/// `app.bsky.feed.getPostThread` into a `PeekPost` (MATRIX-201).
///
/// The rules come from post-peek (https://github.com/tsvb/post-peek, MIT),
/// re-implemented here:
/// - X post text is HTML-escaped (`&amp;`, `&lt;`, `&gt;`), and its entity
///   indices count Unicode scalars, so the text is cut by scalar and each
///   piece is unescaped after the cut. Media links are dropped from the text.
/// - Bluesky facets index UTF-8 bytes, so the text is cut by byte.
/// - A Bluesky post whose author asked to be hidden from logged-out viewers
///   (`!no-unauthenticated` on the author) or that Bluesky's moderators hid
///   (`!hide` on the post, or on the account with the DID as its subject)
///   throws `loggedInOnly` or `hiddenByModerators`. A quoted post of that
///   kind becomes `.unavailable`.
/// - Bluesky media labeled `porn`, `sexual`, `nudity`, `graphic-media` or
///   `gore` sets `mediaWarning`, and `!warn` sets `hasContentWarning`.
/// - Only `http` and `https` links, and only `https` media on the site's
///   media hosts, get into the post.
public enum PostPeekParser {
    // MARK: X

    /// The post of an X syndication answer.
    public static func xPost(from data: Data) throws -> PeekPost {
        guard !data.isEmpty else { throw PostPeekFailure.unavailable }
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data), json.object != nil else {
            throw PostPeekFailure.badResponse
        }
        if json["__typename"]?.string == "TweetTombstone" {
            throw PostPeekFailure.unavailable
        }
        guard let post = xPost(json, nested: false) else { throw PostPeekFailure.badResponse }
        return post
    }

    private static func xPost(_ tweet: JSONValue, nested: Bool) -> PeekPost? {
        guard let id = tweet["id_str"]?.string, PostPeekLink.isXID(id),
              let user = tweet["user"], let screenName = user["screen_name"]?.string, !screenName.isEmpty,
              let url = URL(string: "https://x.com/\(screenName)/status/\(id)")
        else { return nil }

        let author = PeekAuthor(
            name: user["name"]?.string ?? screenName,
            handle: screenName,
            avatarURL: mediaURL(user["profile_image_url_https"]?.string, hosts: xMediaHosts),
            profileURL: URL(string: "https://x.com/\(screenName)"),
            isVerified: user["is_blue_verified"]?.bool == true || user["verified"]?.bool == true
        )
        let photos = tweet["photos"]?.array.compactMap { photo -> PeekPhoto? in
            guard let photoURL = mediaURL(photo["url"]?.string, hosts: xMediaHosts) else { return nil }
            return PeekPhoto(
                url: photoURL,
                alt: photo["accessibilityLabel"]?.string ?? "",
                aspectRatio: ratio(photo["width"]?.number, photo["height"]?.number)
            )
        } ?? []
        let videos = xVideos(tweet)

        var post = PeekPost(
            link: .x(id: id),
            url: url,
            author: author,
            text: xText(tweet),
            photos: photos,
            videos: videos,
            date: date(tweet["created_at"]?.string)
        )
        guard !nested else { return post }

        if photos.isEmpty, videos.isEmpty {
            post.card = xCard(tweet)
        }
        if let quoted = tweet["quoted_tweet"], quoted.object != nil {
            post.quote = xPost(quoted, nested: true).map(PeekQuote.post) ?? .unavailable
        }
        if let replyName = tweet["in_reply_to_screen_name"]?.string, !replyName.isEmpty {
            let parentID = tweet["parent"]?["id_str"]?.string ?? tweet["in_reply_to_status_id_str"]?.string
            let parent = parentID.flatMap { PostPeekLink.isXID($0) ? PostPeekLink.x(id: $0) : nil }
            post.replyTo = PeekReplyContext(link: parent, label: "@\(replyName)")
        }
        return post
    }

    private static func xText(_ tweet: JSONValue) -> [PeekTextRun] {
        let scalars = Array((tweet["text"]?.string ?? "").unicodeScalars)
        let range = tweet["display_text_range"]?.array.compactMap(\.number).map(Int.init) ?? []
        var position = max(0, range.first ?? 0)
        var stop = min(scalars.count, range.count == 2 ? range[1] : scalars.count)

        struct Entity {
            let start: Int
            let end: Int
            let link: URL?
            let label: String?
        }
        var entities: [Entity] = []
        let groups = tweet["entities"]
        func add(_ key: String, _ make: (JSONValue) -> (URL?, String?)?) {
            for entity in groups?[key]?.array ?? [] {
                let indices = entity["indices"]?.array.compactMap(\.number).map(Int.init) ?? []
                guard indices.count == 2, let made = make(entity) else { continue }
                entities.append(Entity(start: indices[0], end: indices[1], link: made.0, label: made.1))
            }
        }
        add("urls") { entity in
            let target = entity["expanded_url"]?.string ?? entity["url"]?.string
            guard let link = webURL(target) else { return nil }
            return (link, entity["display_url"]?.string ?? target)
        }
        add("user_mentions") { entity in
            guard let name = entity["screen_name"]?.string else { return nil }
            return (URL(string: "https://x.com/\(name)"), "@\(name)")
        }
        add("hashtags") { entity in
            guard let tag = entity["text"]?.string else { return nil }
            return (URL(string: "https://x.com/hashtag/\(queryEncoded(tag))"), "#\(tag)")
        }
        add("symbols") { entity in
            guard let symbol = entity["text"]?.string else { return nil }
            return (URL(string: "https://x.com/search?q=%24\(queryEncoded(symbol))"), "$\(symbol)")
        }
        // A media link is dropped from the text: the media shows below it.
        add("media") { _ in (nil, nil) }
        entities.sort { $0.start < $1.start }

        var runs: [PeekTextRun] = []
        func plain(_ from: Int, _ to: Int) {
            guard from < to else { return }
            runs.append(PeekTextRun(unescapeX(String(String.UnicodeScalarView(scalars[from ..< to])))))
        }
        for entity in entities {
            guard entity.start >= position, entity.start < stop else { continue }
            plain(position, entity.start)
            if let label = entity.label {
                runs.append(PeekTextRun(label, link: entity.link))
            }
            // The range counts UTF-16 units and the entities count scalars,
            // so after an emoji a trailing media link can cross the end of
            // the range. The text then ends where that entity starts.
            if entity.end > stop {
                position = entity.start
                stop = entity.start
                break
            }
            position = entity.end
        }
        plain(position, stop)
        return trimmingTrailingWhitespace(runs)
    }

    private static func xVideos(_ tweet: JSONValue) -> [PeekVideo] {
        var videos: [PeekVideo] = []
        for detail in tweet["mediaDetails"]?.array ?? [] {
            let type = detail["type"]?.string
            guard type == "video" || type == "animated_gif" else { continue }
            let info = detail["video_info"]
            let variants = (info?["variants"]?.array ?? [])
                .filter { $0["content_type"]?.string == "video/mp4" }
                .sorted { ($0["bitrate"]?.number ?? 0) > ($1["bitrate"]?.number ?? 0) }
            guard let best = variants.lazy.compactMap({ mediaURL($0["url"]?.string, hosts: xMediaHosts) }).first else { continue }
            let aspect = info?["aspect_ratio"]?.array.compactMap(\.number) ?? []
            videos.append(PeekVideo(
                url: best,
                posterURL: mediaURL(detail["media_url_https"]?.string, hosts: xMediaHosts),
                aspectRatio: aspect.count == 2 ? ratio(aspect[0], aspect[1]) : nil,
                isGIF: type == "animated_gif"
            ))
        }
        if videos.isEmpty, let video = tweet["video"] {
            let variants = (video["variants"]?.array ?? []).filter { $0["type"]?.string == "video/mp4" }
            let aspect = video["aspectRatio"]?.array.compactMap(\.number) ?? []
            if let last = variants.last, let src = mediaURL(last["src"]?.string, hosts: xMediaHosts) {
                videos.append(PeekVideo(
                    url: src,
                    posterURL: mediaURL(video["poster"]?.string, hosts: xMediaHosts),
                    aspectRatio: aspect.count == 2 ? ratio(aspect[0], aspect[1]) : nil
                ))
            }
        }
        return videos
    }

    private static func xCard(_ tweet: JSONValue) -> PeekCard? {
        guard let values = tweet["card"]?["binding_values"] else { return nil }
        let target = values["card_url"]?["string_value"]?.string
            ?? tweet["entities"]?["urls"]?.array.first?["expanded_url"]?.string
        guard let url = webURL(target), let title = values["title"]?["string_value"]?.string, !title.isEmpty else {
            return nil
        }
        let image = ["summary_photo_image_large", "thumbnail_image_large", "photo_image_full_size_large"]
            .lazy.compactMap { values[$0]?["image_value"]?["url"]?.string }.first
        return PeekCard(
            url: url,
            title: title,
            description: values["description"]?["string_value"]?.string,
            imageURL: mediaURL(image, hosts: xMediaHosts),
            domain: values["vanity_url"]?["string_value"]?.string ?? url.host ?? ""
        )
    }

    private static func unescapeX(_ text: String) -> String {
        text.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }

    // MARK: Shared

    static let xMediaHosts: Set = ["pbs.twimg.com", "video.twimg.com"]
    static let blueskyMediaHosts: Set = ["cdn.bsky.app", "video.bsky.app", "video.cdn.bsky.app"]

    /// `string` as an `https` URL on one of `hosts`, or nil.
    static func mediaURL(_ string: String?, hosts: Set<String>) -> URL? {
        guard let string, let url = URL(string: string), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), hosts.contains(host)
        else { return nil }
        return url
    }

    /// `string` as an `http` or `https` URL, or nil.
    static func webURL(_ string: String?) -> URL? {
        guard let string, let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil
        else { return nil }
        return url
    }

    static func ratio(_ width: Double?, _ height: Double?) -> Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return width / height
    }

    static func date(_ string: String?) -> Date? {
        guard let string else { return nil }
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }

    static func queryEncoded(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }

    private static func trimmingTrailingWhitespace(_ runs: [PeekTextRun]) -> [PeekTextRun] {
        var runs = runs
        while let last = runs.last, last.link == nil {
            let trimmed = String(last.text.reversed().drop(while: \.isWhitespace).reversed())
            if trimmed.isEmpty {
                runs.removeLast()
            } else {
                runs[runs.count - 1].text = trimmed
                break
            }
        }
        return runs
    }
}

extension PostPeekLink {
    /// 1 to 25 ASCII digits.
    static func isXID(_ id: String) -> Bool {
        (1 ... 25).contains(id.count) && id.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

extension JSONValue {
    subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else { return nil }
        return object[key]
    }

    var object: [String: JSONValue]? {
        guard case let .object(object) = self else { return nil }
        return object
    }

    var string: String? {
        guard case let .string(string) = self else { return nil }
        return string
    }

    var bool: Bool? {
        guard case let .bool(bool) = self else { return nil }
        return bool
    }

    var number: Double? {
        switch self {
        case let .integer(value): Double(value)
        case let .double(value): value
        default: nil
        }
    }

    var array: [JSONValue] {
        guard case let .array(array) = self else { return [] }
        return array
    }
}
