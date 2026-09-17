import Foundation

/// One reaction pill, reduced to what the pill view's layout depends on
/// (MATRIX-63).
///
/// `MessageReactionView` draws `HStack { Text(key); Text("\(senders.count)") }`
/// inside a fixed padding. Its height is one line of text whatever the tally
/// says, so the tally reaches the layout only through the *width* of the count
/// label — and width only through the digit count, because a wider pill is what
/// can push the strip into compression. `9 → 10` therefore counts as a change;
/// `10 → 11` does not.
public struct ReactionPillGeometry: Equatable, Sendable {
    /// The reaction key, which the pill draws verbatim. Keys are not
    /// interchangeable by length: "👍" and "lgtm" lay out differently.
    public let key: String
    /// Decimal digits in the sender tally, which is the only way the tally
    /// reaches the pill's width.
    public let countDigits: Int

    public init(key: String, senderCount: Int) {
        self.key = key
        countDigits = Self.decimalDigits(of: senderCount)
    }

    /// Digits in `count`, without building a string for it. Called once per
    /// pill per mapped row, so it stays allocation-free on purpose.
    static func decimalDigits(of count: Int) -> Int {
        var magnitude = count.magnitude
        var digits = 1
        while magnitude >= 10 {
            magnitude /= 10
            digits += 1
        }
        return digits
    }
}

/// The reaction strip under a message body, reduced to its height inputs
/// (MATRIX-63).
///
/// `MessageEventBodyView` draws the strip as a **plain `HStack`**, not a
/// wrapping flow layout, so a pill can never start a second line. Two things
/// can still move the strip's height:
///
/// 1. Empty against non-empty. The strip is always in the view tree, but an
///    empty one contributes no pill height, and the two paddings around it
///    (`.padding(.top, hasBottomContent ...)` and the body's
///    `.padding(.bottom, reactions.isEmpty ...)`) switch on emptiness.
/// 2. Compression. When the pills' ideal widths exceed the row, SwiftUI shrinks
///    them toward their minimum widths, and a squeezed `Text` answers by taking
///    a second line. Total ideal width is what decides that, and total ideal
///    width is the key set plus the count-label widths.
///
/// So the strip is fingerprinted by its ordered pills, which covers both. This
/// is deliberately stricter than the geometry strictly requires — a third pill
/// next to two short ones cannot wrap anything on a 1114pt row — because a
/// wrong skip is a stale cached height, which clips the row (the MATRIX-49
/// class of bug). Measuring an extra row costs milliseconds; clipping one is a
/// visible defect.
public struct ReactionStripGeometry: Equatable, Sendable {
    /// The pills, in the order the strip draws them. Order matters only because
    /// comparing arrays is cheaper than comparing sets, and the SDK's order for
    /// a given reaction set is stable.
    public let pills: [ReactionPillGeometry]
    /// Read receipts share the strip's `HStack` and flip the same top padding
    /// through `hasBottomContent`. Only presence matters: the receipt pile is
    /// avatars at a fixed frame, so its height does not vary with how many.
    public let hasReadReceipts: Bool

    /// True when the row draws a reaction strip with content in it.
    public var hasReactions: Bool { !pills.isEmpty }

    public init(pills: [ReactionPillGeometry], hasReadReceipts: Bool) {
        self.pills = pills
        self.hasReadReceipts = hasReadReceipts
    }

    /// Builds the strip from a lazy sequence of key/tally pairs, so a caller
    /// mapping SDK reactions never materialises an intermediate array.
    public init(
        reactions: some Sequence<(key: String, senderCount: Int)>,
        hasReadReceipts: Bool
    ) {
        self.init(
            pills: reactions.map { ReactionPillGeometry(key: $0.key, senderCount: $0.senderCount) },
            hasReadReceipts: hasReadReceipts
        )
    }
}

/// A message body, reduced to its height inputs (MATRIX-63).
///
/// `variant` is the render branch the body takes, as a short literal the mapper
/// supplies from the same switch that builds the view. It exists because
/// `MessageRowKind` is too coarse to separate the branches: a poll and a
/// redaction are both `.other`, and they draw different things. **Two branches
/// must never share a variant string**, or a redaction of a poll would compare
/// equal to the poll.
public struct MessageBodyGeometry: Equatable, Sendable {
    /// Render branch, e.g. `"text"`, `"image"`, `"redacted"`. Mapper-supplied.
    public let variant: String
    /// The plain text that branch lays out. This is the wrapped-line count's
    /// input, so an edited body can never hide behind an equal fingerprint.
    public let text: String
    /// The HTML body a formatted message renders instead of `text`. Both are
    /// kept: `FormattedBodyView` picks between them, and either one changing
    /// can change how many lines the body takes.
    public let formattedText: String?
    /// The SDK's edited flag, which adds an `EditedMarker` line under the body.
    public let isEdited: Bool
    /// Intrinsic media size, which `MediaRowLayout` turns into an aspect ratio
    /// and a height clamp. Nil for a body that draws no media.
    public let mediaWidth: UInt64?
    public let mediaHeight: UInt64?
    /// A video row falls back to a `minHeight` when it has no thumbnail, so
    /// presence is a height input; the thumbnail's identity is not.
    public let hasMediaThumbnail: Bool
    /// The second text run the branch draws under the first: a media caption,
    /// or a location's geo URI. Wraps like any other text.
    public let secondaryText: String?

    public init(
        variant: String,
        text: String,
        formattedText: String? = nil,
        isEdited: Bool = false,
        mediaWidth: UInt64? = nil,
        mediaHeight: UInt64? = nil,
        hasMediaThumbnail: Bool = false,
        secondaryText: String? = nil
    ) {
        self.variant = variant
        self.text = text
        self.formattedText = formattedText
        self.isEdited = isEdited
        self.mediaWidth = mediaWidth
        self.mediaHeight = mediaHeight
        self.hasMediaThumbnail = hasMediaThumbnail
        self.secondaryText = secondaryText
    }
}

/// Everything about a message row that can change its height, and nothing that
/// cannot (MATRIX-63).
///
/// The S-32 cache invalidates on a revision bump, and the drain bumped the
/// revision for *every* content update. A storm is 55% reaction changes, and
/// most of those only re-tally a pill that is already there — height-neutral by
/// construction, yet each one cost a cache miss and a 1.3–3.7ms offscreen
/// SwiftUI measure. This value is the test that separates the two: equal
/// fingerprints mean the row must draw at the height it already has.
///
/// Fields are exact values rather than a digest. A digest would be smaller, but
/// a collision here is a stale height, and a stale height clips the row.
///
/// Deliberately **not** in it, because none of it moves a row's height: the
/// message timestamp (a fixed-width label), hover and focus state (background
/// only), read-receipt *count* (fixed-frame avatars), and the media label
/// fields that draw one-line metadata (mime type, byte size, duration).
public struct TimelineRowHeightFingerprint: Equatable, Sendable {
    public let body: MessageBodyGeometry
    /// Whether the row draws a reply preview: an `EmbeddedMessageView` plus
    /// 10pt of padding above the body.
    ///
    /// Presence, not the replied-to event's identity. The identity costs an FFI
    /// call per mapped row and cannot change without the row becoming a
    /// different event — an edit does not move a reply relation.
    ///
    /// The preview's resolved *text* is not here, and cannot be: reply details
    /// load asynchronously against the timeline object rather than arriving as
    /// a row update, so no fingerprint could see that change either way.
    public let hasReplyPreview: Bool
    /// A thread summary draws an extra line under the body.
    public let hasThreadSummary: Bool
    /// The failure banner a failed local echo draws, which wraps its message.
    /// Nil when the send did not fail.
    public let sendFailureMessage: String?
    /// The name the profile header draws, which changes when a sender's
    /// profile resolves.
    ///
    /// `Username` pins itself to one line today, so this cannot move a height
    /// as the view stands. It is kept anyway: that pin lives in another module
    /// and nothing fails the build if it is removed, and a profile resolving is
    /// not a storm event, so the insurance costs one measure per sender.
    public let senderName: String
    public let reactions: ReactionStripGeometry

    /// True when the row draws a reaction strip, which also picks the row's
    /// view-recycling pool (S-34).
    public var hasReactions: Bool { reactions.hasReactions }

    public init(
        body: MessageBodyGeometry,
        hasReplyPreview: Bool = false,
        hasThreadSummary: Bool = false,
        sendFailureMessage: String? = nil,
        senderName: String,
        reactions: ReactionStripGeometry
    ) {
        self.body = body
        self.hasReplyPreview = hasReplyPreview
        self.hasThreadSummary = hasThreadSummary
        self.sendFailureMessage = sendFailureMessage
        self.senderName = senderName
        self.reactions = reactions
    }

    /// Whether replacing `old` with `new` can be done without re-measuring.
    ///
    /// Conservative by construction, and in three ways:
    ///
    /// - A row without a fingerprint — every row that is not a message — never
    ///   qualifies. Those rows keep the behaviour they had.
    /// - A change of row identity never qualifies, so a row that became a
    ///   different event is measured even if both fingerprints agree.
    /// - Anything the fingerprint does not model counts as a change, because
    ///   the answer is only `true` for an exact match.
    public static func heightIsUnchanged(from old: TimelineRow, to new: TimelineRow) -> Bool {
        guard old.uniqueId == new.uniqueId,
              let oldFingerprint = old.heightFingerprint,
              let newFingerprint = new.heightFingerprint
        else {
            return false
        }
        return oldFingerprint == newFingerprint
    }
}
