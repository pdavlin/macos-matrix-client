import Foundation
import Testing
@testable import TimelineSpikeCore

@Suite("Workload fingerprint")
struct WorkloadFingerprintTests {
    /// The pinned digest of the frozen S-13..S-15 workload.
    ///
    /// This constant is the whole point of the fingerprint. If this test fails, someone
    /// changed `SpikeRowMetrics` or `SpikeCorpus`, every row now lays out differently, and
    /// every JSON dump recorded before the change is no longer comparable with anything
    /// recorded after it. See SCENARIOS.md §10.
    ///
    /// Do not edit this constant to make the test pass. Revert the workload change, or, if
    /// the change is genuinely wanted, re-run every scenario for every candidate and say so
    /// in the story.
    static let frozenFingerprint = "wl1-4246e7b15677d961"

    @Test("The workload fingerprint is the frozen value")
    func fingerprintIsFrozen() {
        #expect(
            WorkloadFingerprint.value == Self.frozenFingerprint,
            "workload changed:\n\(WorkloadFingerprint.canonicalDescription)"
        )
    }

    @Test("The fingerprint does not vary between reads")
    func fingerprintIsStableWithinAProcess() {
        #expect(WorkloadFingerprint.value == WorkloadFingerprint.value)
        #expect(WorkloadFingerprint.canonicalDescription == WorkloadFingerprint.canonicalDescription)
    }

    @Test("The fingerprint is the digest of the canonical description")
    func fingerprintDerivesFromTheDescription() {
        let digest = WorkloadFingerprint.fnv1a64(WorkloadFingerprint.canonicalDescription)
        let hex = String(digest, radix: 16)
        let padded = String(repeating: "0", count: max(0, 16 - hex.count)) + hex
        #expect(WorkloadFingerprint.value == "wl\(WorkloadFingerprint.formatVersion)-\(padded)")
    }

    @Test("The digest is always sixteen hex digits after the version tag")
    func fingerprintShapeIsFixed() {
        let parts = WorkloadFingerprint.value.split(separator: "-")
        #expect(parts.count == 2)
        #expect(parts.first == "wl1")
        #expect(parts.last?.count == 16)
        #expect(parts.last?.allSatisfy(\.isHexDigit) == true)
    }

    @Test("Every metric constant contributes exactly one named line")
    func everyMetricIsNamedOnce() {
        let lines = WorkloadFingerprint.canonicalDescription.split(separator: "\n")
        let metricNames = lines
            .filter { $0.hasPrefix("metric.") }
            .compactMap { $0.split(separator: "=").first.map(String.init) }
        #expect(metricNames.count == 14)
        // A copy-paste slip that fingerprints the same constant twice would silently stop
        // covering the other one.
        #expect(Set(metricNames).count == metricNames.count)
    }

    @Test("The description records the metric constants exactly, not a rounded form")
    func metricsEnterAsBitPatterns() {
        let description = WorkloadFingerprint.canonicalDescription
        let expected = String(Double(SpikeRowMetrics.bodyFontSize).bitPattern, radix: 16)
        #expect(description.contains("metric.bodyFontSize=\(expected)"))
        // 34 pt is exactly representable; the point of the bit pattern is that a value
        // that is not, such as 4.1, would still round-trip.
        #expect(description.contains("metric.daySeparatorHeight=4041000000000000"))
    }

    @Test("The image-size probes cover each clamp branch")
    func imageProbesAreDistinct() {
        let lines = WorkloadFingerprint.canonicalDescription
            .split(separator: "\n")
            .filter { $0.hasPrefix("image.") }
        #expect(lines.count == 5)
        // Five probes that all produced the same size would test nothing.
        let sizes = lines.compactMap { $0.split(separator: "=").last.map(String.init) }
        #expect(Set(sizes).count == 5)
    }

    @Test("The corpus is part of the workload")
    func corpusIsCovered() {
        #expect(WorkloadFingerprint.canonicalDescription.contains("corpus="))
    }
}

@Suite("FNV-1a")
struct FNVTests {
    @Test("Published 64-bit test vectors")
    func knownVectors() {
        #expect(WorkloadFingerprint.fnv1a64("") == 0xCBF2_9CE4_8422_2325)
        #expect(WorkloadFingerprint.fnv1a64("a") == 0xAF63_DC4C_8601_EC8C)
        #expect(WorkloadFingerprint.fnv1a64("foobar") == 0x8594_4171_F739_67E8)
    }

    @Test("Order matters, so two constants cannot be swapped unnoticed")
    func orderSensitive() {
        #expect(WorkloadFingerprint.fnv1a64("ab") != WorkloadFingerprint.fnv1a64("ba"))
        #expect(WorkloadFingerprint.fnv1a64("ab") == 0x089C_4407_B545_986A)
    }

    @Test("A one-character change moves the digest")
    func sensitiveToSmallChanges() {
        let base = WorkloadFingerprint.fnv1a64("metric.bodyFontSize=402a000000000000")
        let changed = WorkloadFingerprint.fnv1a64("metric.bodyFontSize=402b000000000000")
        #expect(base != changed)
    }

    @Test("Multi-byte scalars are hashed by their UTF-8 bytes, not by scalar value")
    func hashesUTF8Bytes() {
        // The reaction pool is emoji, so the digest must be defined over bytes.
        #expect(WorkloadFingerprint.fnv1a64("\u{1F44D}") != WorkloadFingerprint.fnv1a64("?"))
        #expect(WorkloadFingerprint.fnv1a64("\u{1F44D}") == WorkloadFingerprint.fnv1a64("👍"))
    }
}
