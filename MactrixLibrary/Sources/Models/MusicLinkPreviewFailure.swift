import Foundation

/// Why the homeserver's URL preview of a Spotify link gave no JSON, for the
/// title of a music link (MATRIX-191).
///
/// The read is the SDK's `Client.getUrlPreview(url:ts:)` (MATRIX-219, see
/// `MatrixClient+MusicLinkTitles.swift` in `Core`). The SDK sends the
/// authenticated `GET /_matrix/client/v1/media/preview_url?url=<link>` to the
/// homeserver of the session. The homeserver fetches the page, not the app.
/// The server allows previews for `open.spotify.com` only
/// (`/etc/matrix-synapse/conf.d/url-preview.yaml`), so any other URL gets a
/// 403 with a Matrix error code.
///
/// `Core` maps the SDK's answer and errors to this type, so
/// `MusicLinkTitleStore` can tell an answer of the server (kept for an hour)
/// from a read that got no Matrix answer (kept for a short time). A value
/// holds no token, no URL, and no message text of the SDK, so it is safe to
/// log.
public enum MusicLinkPreviewFailure: Error, Equatable, Sendable {
    /// The link to preview is not an `https` URL. The app sends no read.
    case badLink
    /// The homeserver answered with a Matrix error, for example `M_UNKNOWN`
    /// for a link that the server's preview settings block.
    case homeserver(errcode: String)
    /// The homeserver answered with no preview.
    case noPreview
    /// The read got no Matrix answer: no network, a timeout, or an HTTP
    /// error with no Matrix error body. The SDK's message is dropped, because
    /// it can hold the URL.
    case transport

    /// True for a failure that a new read soon can fix: `transport`.
    public var isTransient: Bool {
        self == .transport
    }

    /// True if a read that failed with `error` is worth a new read soon: a
    /// `transport` failure, and any error that is not of this type.
    public static func isTransient(_ error: Error) -> Bool {
        (error as? MusicLinkPreviewFailure)?.isTransient ?? true
    }

    /// A short name for an error, safe for the log: the case of a
    /// `MusicLinkPreviewFailure`, else the error's domain and code. Never the
    /// description, which can hold a URL.
    public static func logName(of error: Error) -> String {
        if let failure = error as? MusicLinkPreviewFailure {
            return String(describing: failure)
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }
}
