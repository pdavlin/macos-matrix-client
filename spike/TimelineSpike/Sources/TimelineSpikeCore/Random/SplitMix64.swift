import Foundation

/// A small, fully deterministic pseudo-random generator.
///
/// The spike needs bit-for-bit reproducible data across machines and across runs, so the
/// standard library's `SystemRandomNumberGenerator` is unusable and even
/// `Int.random(in:using:)` is avoided: its bit consumption is an implementation detail of
/// the standard library. Every draw in this package goes through the explicit helpers
/// below, so a seed pins the output exactly.
public struct SplitMix64: RandomNumberGenerator, Sendable {
    private static let gamma: UInt64 = 0x9E37_79B9_7F4A_7C15

    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= Self.gamma
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// An unbiased draw in `0..<upperBound` using Lemire-style rejection.
    public mutating func value(below upperBound: UInt64) -> UInt64 {
        precondition(upperBound > 0, "upperBound must be positive")
        let threshold = (0 &- upperBound) % upperBound
        while true {
            let candidate = next()
            if candidate >= threshold {
                return candidate % upperBound
            }
        }
    }

    /// An unbiased draw from a half-open integer range.
    public mutating func int(in range: Range<Int>) -> Int {
        precondition(!range.isEmpty, "range must not be empty")
        return range.lowerBound + Int(value(below: UInt64(range.count)))
    }

    /// An unbiased draw from a closed integer range.
    public mutating func int(in range: ClosedRange<Int>) -> Int {
        int(in: range.lowerBound ..< (range.upperBound + 1))
    }

    /// A draw in `[0, 1)` with 53 bits of resolution.
    public mutating func unitDouble() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// A draw in `[lower, upper)`.
    public mutating func double(in range: Range<Double>) -> Double {
        range.lowerBound + unitDouble() * (range.upperBound - range.lowerBound)
    }

    /// Returns `true` with the given probability.
    public mutating func chance(_ probability: Double) -> Bool {
        unitDouble() < probability
    }

    /// Picks one element of a non-empty collection.
    public mutating func element<C: RandomAccessCollection>(of collection: C) -> C.Element
        where C.Index == Int
    {
        precondition(!collection.isEmpty, "collection must not be empty")
        return collection[collection.startIndex + int(in: 0 ..< collection.count)]
    }

    /// Derives an independent seed from a base seed and a salt.
    ///
    /// Used to give every generated chunk its own stream while keeping the whole timeline
    /// reproducible from one root seed.
    public static func derivedSeed(from seed: UInt64, salt: Int) -> UInt64 {
        var generator = SplitMix64(seed: seed ^ (UInt64(bitPattern: Int64(salt)) &* gamma))
        _ = generator.next()
        return generator.next()
    }
}
