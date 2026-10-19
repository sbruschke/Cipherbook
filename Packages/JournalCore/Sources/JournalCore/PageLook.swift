import Foundation

public struct Pt: Hashable, Codable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
}

public struct PresetStyle: Equatable {
    public let baseHex: String
    public let edgeHex: String
    public let inkHex: String
    /// 0 (pristine) … 1 (heavily worn): drives tears, stains and creases.
    public let wear: Double

    public init(baseHex: String, edgeHex: String, inkHex: String, wear: Double) {
        self.baseHex = baseHex; self.edgeHex = edgeHex; self.inkHex = inkHex; self.wear = wear
    }
}

public enum Preset: String, CaseIterable, Codable {
    case aged, vellum, linen, slate

    public var style: PresetStyle {
        switch self {
        case .aged:   return PresetStyle(baseHex: "#e6d3a3", edgeHex: "#a9824a", inkHex: "#3b2a1a", wear: 0.9)
        case .vellum: return PresetStyle(baseHex: "#f1e6c8", edgeHex: "#c9b27a", inkHex: "#2f2418", wear: 0.35)
        case .linen:  return PresetStyle(baseHex: "#ece6d8", edgeHex: "#b8ad94", inkHex: "#26313d", wear: 0.5)
        case .slate:  return PresetStyle(baseHex: "#2a2d33", edgeHex: "#14161a", inkHex: "#e8dfc9", wear: 0.6)
        }
    }
}

public struct Stain: Equatable { public var center: Pt; public var radius: Double; public var opacity: Double }
public struct Crease: Equatable { public var a: Pt; public var b: Pt; public var bend: Double; public var opacity: Double }
public struct Speckle: Equatable { public var at: Pt; public var radius: Double; public var opacity: Double }

public struct PageLook: Equatable {
    public static let edgePointsPerSide = 12

    /// Closed loop, clockwise from the top-left, in the unit square (edges wobble slightly outside/inside).
    public var outline: [Pt]
    public var stains: [Stain]
    public var creases: [Crease]
    public var speckles: [Speckle]
    /// Added to the base color's brightness, about ±0.06.
    public var brightness: Double
    /// Multiplies the nominal page width (0.97 … 1.03): pages differ slightly in shape.
    public var widthScale: Double
    /// Resting angle in degrees, ±2.5.
    public var rotation: Double
    /// Lift of each corner (TL, TR, BR, BL), 0…1, for the shadow/curl hint.
    public var cornerCurl: [Double]

    public static func make(seed: UInt64, preset: Preset) -> PageLook {
        let wear = preset.style.wear
        var edge = SplitMix64(seed: deriveSeed(seed, 1))
        var surface = SplitMix64(seed: deriveSeed(seed, 2))
        var shape = SplitMix64(seed: deriveSeed(seed, 3))

        let n = edgePointsPerSide
        // Smooth per-point wobble: raw noise averaged with its neighbours.
        let raw = (0..<(4 * n)).map { _ in edge.unit() }
        let amp = 0.004 + 0.010 * wear
        let wobble: [Double] = (0..<(4 * n)).map { i in
            let a = raw[(i + 4 * n - 1) % (4 * n)], b = raw[i], c = raw[(i + 1) % (4 * n)]
            return max(-0.01, ((a + b + c) / 3 - 0.35) * amp * 2)
        }

        // Tears: a triangular bite out of one edge.
        let tearCount = Int(edge.unit() * wear * 4)
        var tearBites = [Double](repeating: 0, count: 4 * n)
        for _ in 0..<tearCount {
            let side = edge.int(0...3)
            let center = edge.range(0.1, 0.9)
            let half = edge.range(0.06, 0.16)
            let depth = edge.range(0.015, 0.05) * (0.5 + wear)
            for i in 0..<n {
                let t = Double(i) / Double(n)
                let d = abs(t - center)
                if d < half { tearBites[side * n + i] += depth * (1 - d / half) }
            }
        }

        var outline: [Pt] = []
        for side in 0..<4 {
            for i in 0..<n {
                let t = Double(i) / Double(n)
                let base: Pt, inward: Pt
                switch side {
                case 0:  base = Pt(t, 0);     inward = Pt(0, 1)
                case 1:  base = Pt(1, t);     inward = Pt(-1, 0)
                case 2:  base = Pt(1 - t, 1); inward = Pt(0, -1)
                default: base = Pt(0, 1 - t); inward = Pt(1, 0)
                }
                let off = wobble[side * n + i] + tearBites[side * n + i]
                outline.append(Pt(base.x + inward.x * off, base.y + inward.y * off))
            }
        }

        let stainCount = Int(surface.unit() * (1 + wear * 5))
        let stains = (0..<stainCount).map { _ in
            Stain(center: Pt(surface.range(0.05, 0.95), surface.range(0.05, 0.95)),
                  radius: surface.range(0.04, 0.22),
                  opacity: surface.range(0.04, 0.16) * (0.5 + wear))
        }
        let creaseCount = Int(surface.unit() * (1 + wear * 3))
        let creases = (0..<creaseCount).map { _ in
            Crease(a: Pt(surface.range(0, 1), surface.range(0, 1)),
                   b: Pt(surface.range(0, 1), surface.range(0, 1)),
                   bend: surface.range(-0.08, 0.08),
                   opacity: surface.range(0.05, 0.2))
        }
        let speckles = (0..<Int(30 + 90 * wear)).map { _ in
            Speckle(at: Pt(surface.unit(), surface.unit()),
                    radius: surface.range(0.0015, 0.004),
                    opacity: surface.range(0.05, 0.25))
        }

        return PageLook(
            outline: outline, stains: stains, creases: creases, speckles: speckles,
            brightness: shape.range(-0.06, 0.06),
            widthScale: shape.range(0.97, 1.03),
            rotation: shape.range(-2.5, 2.5),
            cornerCurl: (0..<4).map { _ in shape.unit() * wear })
    }
}
