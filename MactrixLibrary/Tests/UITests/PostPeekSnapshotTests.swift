import AppKit
import Models
import SnapshotTesting
import SwiftUI
import Testing
import Tokens
@testable import UI

/// MATRIX-201: the post peek popover's content, in light and dark: a text
/// post, a post with a photo, a post that quotes another, and a failed
/// read.
///
/// The images are solid fills put in the store, so no test reads the
/// network. The date draws in UTC and en_US. The height checks also run on
/// CI, because they do not depend on font rasterization.
@MainActor
struct PostPeekSnapshotTests {
    private nonisolated static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func name(_ appearance: NSAppearance.Name) -> String {
        appearance == .darkAqua ? "dark" : "light"
    }

    private static func url(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    private static let avatar = url("https://pbs.twimg.com/profile_images/1/jack_normal.jpg")
    private static let blueskyAvatar = url("https://cdn.bsky.app/img/avatar/plain/did:plc:a/b")
    private static let quoteAvatar = url("https://cdn.bsky.app/img/avatar/plain/did:plc:c/d")
    private static let photo = url("https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:a/e")

    private static func image(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            color.setFill()
            rect.fill()
            return true
        }
    }

    private static func store() -> PostPeekStore {
        let store = PostPeekStore(
            fetchPost: { _ in throw PostPeekFailure.network },
            fetchImage: { _ in throw PostPeekFailure.network }
        )
        store.rememberImage(image(.systemBlue), for: avatar)
        store.rememberImage(image(.systemIndigo), for: blueskyAvatar)
        store.rememberImage(image(.systemOrange), for: quoteAvatar)
        store.rememberImage(image(.systemTeal), for: photo)
        return store
    }

    private static let date = Date(timeIntervalSince1970: 1_142_974_214)

    static let textPost = PeekPost(
        link: .x(id: "20"),
        url: url("https://x.com/jack/status/20"),
        author: PeekAuthor(name: "jack", handle: "jack", avatarURL: avatar, profileURL: url("https://x.com/jack"), isVerified: true),
        text: [PeekTextRun("just setting up my twttr")],
        date: date
    )

    static let photoPost = PeekPost(
        link: .bluesky(actor: "did:plc:a", rkey: "3n2m24be4e223"),
        url: url("https://bsky.app/profile/bsky.app/post/3n2m24be4e223"),
        author: PeekAuthor(name: "Bluesky", handle: "bsky.app", avatarURL: blueskyAvatar),
        text: [
            PeekTextRun("Encrypted DMs from your Bluesky profile, now for Android and iOS!\n\nTry it: "),
            PeekTextRun("@germnetwork.com", link: url("https://bsky.app/profile/did:plc:g")),
        ],
        photos: [PeekPhoto(url: photo, alt: "The Germ DM button", aspectRatio: 1)],
        date: date
    )

    static let quotePost = PeekPost(
        link: .bluesky(actor: "did:plc:a", rkey: "3n27yge3hys24"),
        url: url("https://bsky.app/profile/bsky.app/post/3n27yge3hys24"),
        author: PeekAuthor(name: "Bluesky", handle: "bsky.app", avatarURL: blueskyAvatar),
        text: [PeekTextRun("I heard Bluesky gets all its breaking news from Flavor Flav")],
        quote: .post(PeekPost(
            link: .bluesky(actor: "did:plc:c", rkey: "3n27ufkokmk2p"),
            url: url("https://bsky.app/profile/flavorflav.bsky.social/post/3n27ufkokmk2p"),
            author: PeekAuthor(name: "FLAVOR FLAV ⏰", handle: "flavorflav.bsky.social", avatarURL: quoteAvatar, isVerified: true),
            text: [PeekTextRun("Nationwide ground stop on all flights in the US.")]
        )),
        replyTo: PeekReplyContext(link: .x(id: "1"), label: "@flavorflav.bsky.social"),
        date: date
    )

    private func model(_ state: PostPeekModel.State, link: PostPeekLink = .x(id: "20")) -> PostPeekModel {
        PostPeekModel(link: link, fallbackURL: link.webURL, store: Self.store(), state: state)
    }

    private func host(_ model: PostPeekModel, appearance: NSAppearance.Name = .aqua) -> NSHostingController<AnyView> {
        let controller = NSHostingController(
            rootView: AnyView(
                PostPeekView(model: model)
                    .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .current)
                    .environment(\.locale, Locale(identifier: "en_US"))
                    .background(Color(NSColor.windowBackgroundColor))
            )
        )
        controller.view.frame.size = controller.view.fittingSize
        // Pin the appearance, so the snapshot does not follow the system's.
        controller.view.appearance = NSAppearance(named: appearance)
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func text(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(model(.loaded(Self.textPost)), appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func photo(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(model(.loaded(Self.photoPost)), appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func quote(appearance: NSAppearance.Name) {
        assertSnapshot(of: host(model(.loaded(Self.quotePost)), appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CI"] == nil), arguments: appearances)
    func error(appearance: NSAppearance.Name) {
        let model = model(.failed(.loggedInOnly), link: .bluesky(actor: "bsky.app", rkey: "3n2m24be4e223"))
        assertSnapshot(of: host(model, appearance: appearance), as: .scaledImage, named: name(appearance))
    }

    // MARK: Size

    @Test func thePopoverIsFixedWidth() {
        for state in [PostPeekModel.State.loading, .loaded(Self.textPost), .loaded(Self.quotePost), .failed(.network)] {
            #expect(host(model(state)).view.fittingSize.width == PostPeekToken.width)
        }
    }

    /// A short post takes its own height. A long one stops at the maximum
    /// and scrolls.
    @Test func aLongPostScrolls() {
        let short = host(model(.loaded(Self.textPost))).view.fittingSize.height
        #expect(short > 0)
        #expect(short < PostPeekToken.maxHeight / 2)

        var long = Self.textPost
        long.text = [PeekTextRun(Array(repeating: "A long line of post text that wraps.", count: 80).joined(separator: " "))]
        #expect(host(model(.loaded(long))).view.fittingSize.height == PostPeekToken.maxHeight)
    }

    /// A photo draws as wide as the content, at its own ratio, but never
    /// taller than `singleMediaMaxHeight`.
    @Test func aPhotoIsAsWideAsTheContent() {
        var withoutPhoto = Self.photoPost
        withoutPhoto.photos = []
        let without = host(model(.loaded(withoutPhoto))).view.fittingSize.height
        let contentWidth = PostPeekToken.width - 2 * PostPeekToken.padding

        func added(ratio: Double) -> CGFloat {
            var post = Self.photoPost
            post.photos[0].aspectRatio = ratio
            return host(model(.loaded(post))).view.fittingSize.height - without - PostPeekToken.spacing
        }
        #expect(abs(added(ratio: 2) - contentWidth / 2) <= 1)
        // A square photo would be taller than the maximum.
        #expect(abs(added(ratio: 1) - PostPeekToken.singleMediaMaxHeight) <= 1)
    }

    @Test func backShowsThePageBefore() {
        let model = model(.loaded(Self.textPost))
        #expect(!model.canGoBack)
        model.open(.x(id: "1"))
        #expect(model.canGoBack)
        #expect(model.page.link == .x(id: "1"))
        #expect(model.page.state == .loading)
        model.back()
        #expect(!model.canGoBack)
        #expect(model.page.state == .loaded(Self.textPost))
    }

    @Test func aFailedReadShowsTheFailure() async {
        let model = model(.loading)
        model.start()
        for _ in 0 ..< 100 where model.page.state == .loading {
            await Task.yield()
        }
        #expect(model.page.state == .failed(.network))
    }
}
