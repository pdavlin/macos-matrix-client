import Foundation

/// A stable digest of the per-row workload every candidate renders.
///
/// ## Why this exists
///
/// The S-15 decision compares frame times from two different processes, run on two
/// different days, by two different people. Those numbers are only comparable when both
/// runs laid out the same amount of content per row. Nothing in the JSON report used to
/// record that: a one-character edit to `SpikeRowMetrics.bodyFontSize` changes every row
/// height and every frame time, and the two dumps still look like a fair comparison.
///
/// `SpikeReport.workloadFingerprint` closes that hole. Two dumps with different
/// fingerprints were produced by different workloads and must not be put in the same
/// table.
///
/// ## What is covered
///
/// - Every numeric constant in `SpikeRowMetrics`.
/// - The behaviour of `SpikeRowMetrics.imageSize(for:availableWidth:)`, sampled at fixed
///   inputs. Sampling the function rather than only its constants catches an edit to the
///   clamping formula, not just to the numbers it clamps against.
/// - A digest of `SpikeCorpus`. The report already carries the seed, but the seed only
///   fixes *which* corpus entries are drawn. Editing a word pool changes the text at every
///   index, so the corpus is part of the workload.
///
/// ## What is not covered, and why
///
/// - The *structure* of `SpikeRowView`: a `View` is not introspectable, so adding a row of
///   chrome cannot be detected here.
/// - Font weights and designs, which are baked into `Font` values that have no stable,
///   documented textual form. Deriving the fingerprint from `String(describing:)` on a
///   `Font` would make it vary by OS build, which would defeat cross-machine comparison —
///   a worse failure than the gap it closes.
///
/// Both gaps are covered by policy instead: SCENARIOS.md §10 freezes `SpikeRowView` and
/// `SpikeRowMetrics` for the S-13..S-15 window.
///
/// ## Stability
///
/// The digest is FNV-1a over a canonical byte string, not Swift's `Hashable`. Swift seeds
/// its hasher per process, so `hashValue` differs between two runs of the same binary and
/// is useless for this job. Doubles enter the canonical string as their IEEE-754 bit
/// patterns, so no number formatting, locale or rounding can move the result.
public enum WorkloadFingerprint {
    /// Bumped by hand when the *composition* of the fingerprint changes, so that an old
    /// dump and a new dump of an unchanged workload are still visibly different documents.
    public static let formatVersion = 1

    /// The value written into every report, for example `wl1-6f3c9a12b4d5e6f7`.
    public static let value: String = {
        let digest = fnv1a64(canonicalDescription)
        let hex = String(digest, radix: 16)
        let padded = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        return "wl\(formatVersion)-\(padded)"
    }()

    /// The exact byte string the digest is taken over. Exposed so a failing fingerprint
    /// test can print what changed rather than only that something changed.
    public static var canonicalDescription: String {
        var lines: [String] = ["version=\(formatVersion)"]
        for (name, number) in metricConstants {
            lines.append("metric.\(name)=\(bits(number))")
        }
        for sample in imageSizeSamples {
            lines.append(sample)
        }
        lines.append("corpus=\(bits(corpusDigest))")
        return lines.joined(separator: "\n")
    }

    // MARK: - Components

    /// Every constant in `SpikeRowMetrics` that can move a row's height or width.
    ///
    /// The list is written out by hand because Swift cannot enumerate the static members
    /// of an enum. A new constant that is not added here is not fingerprinted; the test
    /// suite pins the resulting digest, so adding a constant without adding it here at
    /// least fails loudly the moment the constant is used and the pinned value moves.
    private static var metricConstants: [(String, CGFloat)] {
        [
            ("horizontalPadding", SpikeRowMetrics.horizontalPadding),
            ("verticalPadding", SpikeRowMetrics.verticalPadding),
            ("runLeadingInset", SpikeRowMetrics.runLeadingInset),
            ("avatarSize", SpikeRowMetrics.avatarSize),
            ("avatarTextGap", SpikeRowMetrics.avatarTextGap),
            ("headerBodyGap", SpikeRowMetrics.headerBodyGap),
            ("reactionTopGap", SpikeRowMetrics.reactionTopGap),
            ("daySeparatorHeight", SpikeRowMetrics.daySeparatorHeight),
            ("bodyFontSize", SpikeRowMetrics.bodyFontSize),
            ("headerFontSize", SpikeRowMetrics.headerFontSize),
            ("metaFontSize", SpikeRowMetrics.metaFontSize),
            ("maximumImageWidth", SpikeRowMetrics.maximumImageWidth),
            ("minimumImageHeight", SpikeRowMetrics.minimumImageHeight),
            ("maximumImageHeight", SpikeRowMetrics.maximumImageHeight)
        ]
    }

    /// Fixed probe points chosen to exercise every branch of `imageSize`: the intrinsic
    /// width, the maximum width clamp, the available width clamp, the minimum height clamp
    /// and the maximum height clamp.
    private static var imageSizeSamples: [String] {
        let probes: [(aspectRatio: Double, intrinsicWidth: Double, availableWidth: CGFloat)] = [
            (1.0, 200, 600),
            (1.6, 900, 600),
            (1.6, 900, 300),
            (8.0, 400, 600),
            (0.2, 400, 600)
        ]
        return probes.enumerated().map { index, probe in
            let placeholder = ImagePlaceholder(
                aspectRatio: probe.aspectRatio,
                intrinsicWidth: probe.intrinsicWidth,
                hue: 0,
                caption: nil
            )
            let size = SpikeRowMetrics.imageSize(
                for: placeholder,
                availableWidth: probe.availableWidth
            )
            return "image.\(index)=\(bits(size.width)),\(bits(size.height))"
        }
    }

    /// A digest of the frozen text pools. Their contents decide how tall a text row is at
    /// any given width, so they belong to the workload just as much as the paddings do.
    private static var corpusDigest: UInt64 {
        var parts: [String] = [
            "words:\(SpikeCorpus.words.count)",
            "reactions:\(SpikeCorpus.reactionKeys.count)",
            "captions:\(SpikeCorpus.captions.count)"
        ]
        parts.append(contentsOf: SpikeCorpus.words)
        parts.append(contentsOf: SpikeCorpus.reactionKeys)
        parts.append(contentsOf: SpikeCorpus.captions)
        return fnv1a64(parts.joined(separator: "\u{1F}"))
    }

    // MARK: - Primitives

    /// The IEEE-754 bit pattern in hex. Exact, and immune to locale and rounding.
    private static func bits(_ value: CGFloat) -> String {
        String(Double(value).bitPattern, radix: 16)
    }

    private static func bits(_ value: UInt64) -> String {
        String(value, radix: 16)
    }

    /// FNV-1a, 64 bit, over the UTF-8 bytes of `string`.
    ///
    /// Not a cryptographic hash and not meant to be one. The threat model is an honest
    /// mistake, not an adversary: the job is to make two different workloads produce two
    /// visibly different strings.
    static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        let prime: UInt64 = 0x0000_0100_0000_01B3
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
