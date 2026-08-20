import Foundation

/// Fixed word and emoji pools for the generator.
///
/// Changing any array changes every generated timeline, which invalidates comparisons
/// against previously recorded runs. Treat these as frozen for the life of the spike.
public enum SpikeCorpus {
    public static let words: [String] = [
        "bridge", "backfill", "sync", "keyshare", "decrypt", "verify", "device", "session",
        "timeline", "anchor", "prepend", "scroll", "hitch", "frame", "layout", "measure",
        "reaction", "redaction", "edit", "reply", "thread", "room", "invite", "sidebar",
        "toolbar", "glass", "opaque", "snapshot", "regression", "deterministic", "seed",
        "harness", "candidate", "budget", "percentile", "drift", "viewport", "clip",
        "column", "table", "collection", "lazy", "stack", "identity", "diff", "invalidate",
        "recycle", "height", "estimate", "paragraph", "wrap", "kern", "baseline", "avatar",
        "roster", "separator", "boundary", "calendar", "timestamp", "monotonic", "window",
        "contiguous", "index", "cache", "store", "keychain", "entitlement", "signing",
        "toolchain", "pinned", "vendored", "signature", "binding", "shell", "native",
        "shortcut", "quicklook", "notification", "unread", "marker", "typing", "presence"
    ]

    public static let reactionKeys: [String] = [
        "\u{1F44D}", "\u{1F389}", "\u{2764}\u{FE0F}", "\u{1F602}",
        "\u{1F680}", "\u{1F440}", "\u{1F525}", "\u{2705}"
    ]

    public static let captions: [String] = [
        "screenshot from the run",
        "instruments trace",
        "before and after",
        "the hitch is visible here",
        "attached from the bridge"
    ]
}
