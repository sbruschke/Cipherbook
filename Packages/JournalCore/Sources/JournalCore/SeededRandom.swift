import Foundation

/// Deterministic generator: the same seed yields the same sequence on every platform.
public struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(UInt64(1) << 53)
    }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double {
        lo + (hi - lo) * unit()
    }

    public mutating func int(_ r: ClosedRange<Int>) -> Int {
        r.lowerBound + Int(next() % UInt64(r.count))
    }
}

/// An independent seed for a sub-feature (stains, creases, fasteners …) of one page.
public func deriveSeed(_ seed: UInt64, _ salt: UInt64) -> UInt64 {
    var g = SplitMix64(seed: seed ^ (salt &* 0xD6E8_FEB8_6659_FD93))
    return g.next()
}
