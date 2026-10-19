import Foundation

public enum FastenerKind: String, Codable, CaseIterable { case pin, staple, tape }

/// A fastener attached to a stack. The seed is a decimal string on the wire.
public struct Fastener: Codable, Equatable {
    public var kind: FastenerKind
    public var seed: String
    public init(kind: FastenerKind, seed: String) { self.kind = kind; self.seed = seed }
    public var seedValue: UInt64 { UInt64(seed) ?? 0 }
}

public struct FastenerLook: Equatable {
    /// Position on the top page in unit coordinates (y near the top edge).
    public var position: Pt
    public var angle: Double
    public var size: Double
    public var wear: Double

    public static func make(kind: FastenerKind, seed: UInt64) -> FastenerLook {
        var g = SplitMix64(seed: deriveSeed(seed, 11))
        switch kind {
        case .pin:
            return FastenerLook(position: Pt(g.range(0.42, 0.58), g.range(0.02, 0.07)),
                                angle: g.range(-12, 12), size: g.range(0.9, 1.1), wear: g.unit())
        case .staple:
            let left = g.unit() < 0.5
            return FastenerLook(position: Pt(left ? g.range(0.04, 0.12) : g.range(0.88, 0.96), g.range(0.02, 0.1)),
                                angle: left ? g.range(25, 55) : g.range(-55, -25), size: g.range(0.9, 1.1), wear: g.unit())
        case .tape:
            return FastenerLook(position: Pt(g.range(0.35, 0.65), g.range(0.0, 0.04)),
                                angle: g.range(-9, 9), size: g.range(0.9, 1.15), wear: g.unit())
        }
    }
}
