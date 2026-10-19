import Foundation

public struct WordArtStroke: Equatable {
    public var a: Pt
    public var c: Pt
    public var b: Pt
    public var barbL: Pt?
    public var barbR: Pt?
    public var widthA: Double
    public var widthB: Double
    public var tone: Double
    public var wordIndex: Int
}

public struct PageRect: Equatable {
    public var minX: Double, minY: Double, maxX: Double, maxY: Double
    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX; self.minY = minY; self.maxX = maxX; self.maxY = maxY
    }
}

public struct WordArtPlacement: Equatable {
    public var center: Pt
    public var size: Double
    public var rotation: Double

    /// Axis-aligned bounds, in the page unit square, of the rotated doodle square.
    public var frame: PageRect {
        let d = WordArtDrawing(strokes: [], center: center, size: size, rotation: rotation)
        let corners = [Pt(-0.5, -0.5), Pt(0.5, -0.5), Pt(0.5, 0.5), Pt(-0.5, 0.5)].map(d.pagePoint)
        return PageRect(minX: corners.map(\.x).min()!, minY: corners.map(\.y).min()!,
                        maxX: corners.map(\.x).max()!, maxY: corners.map(\.y).max()!)
    }
}

public struct WordArtDrawing: Equatable {
    public var strokes: [WordArtStroke]
    /// Centre of the doodle in the page's unit square.
    public var center: Pt
    /// Width of the doodle as a fraction of the page width.
    public var size: Double
    /// Degrees.
    public var rotation: Double

    public var isEmpty: Bool { strokes.isEmpty }
    public static let empty = WordArtDrawing(strokes: [], center: Pt(0.5, 0.5), size: 0, rotation: 0)

    /// Art space (−0.5…0.5, square) → the page's unit square. The doodle is square in *points*
    /// (width = size × page width), so y is scaled by the 240:320 page ratio.
    public func pagePoint(_ p: Pt) -> Pt {
        let r = rotation * .pi / 180
        let x = p.x * size, y = p.y * size
        return Pt(center.x + x * cos(r) - y * sin(r),
                  center.y + (x * sin(r) + y * cos(r)) * WordArt.pageWidthOverHeight)
    }
}

public enum WordArt {
    public static let maxWords = 120
    public static let maxCharsPerWord = 30
    public static let pageWidthOverHeight = 240.0 / 320.0

    public static func splitWords(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    public static func make(text: String, seed: UInt64) -> WordArtDrawing {
        var chains: [[V3]] = []
        for w in splitWords(text) {
            let vs = w.compactMap { LegacyVectors.vectors[$0] }.prefix(maxCharsPerWord)
            if !vs.isEmpty { chains.append(Array(vs)) }
            if chains.count == maxWords { break }
        }
        guard !chains.isEmpty else { return .empty }

        // Camera: fixed per page, independent of the text, so typing never spins the picture.
        var cam = SplitMix64(seed: deriveSeed(seed, 21))
        let yaw = cam.range(0, 2 * .pi), pitch = cam.range(0.35, 1.2)
        func project(_ p: V3) -> Pt {
            let x1 = p.x * cos(yaw) + p.z * sin(yaw)
            let z1 = -p.x * sin(yaw) + p.z * cos(yaw)
            return Pt(x1, p.y * cos(pitch) - z1 * sin(pitch))
        }

        var strokes: [WordArtStroke] = []
        for (wi, chain) in chains.enumerated() {
            let tone = chains.count > 1 ? Double(wi) / Double(chains.count - 1) : 1
            var pos = V3(x: 0, y: 0, z: 0)
            for (ci, v) in chain.enumerated() {
                let next = V3(x: pos.x + v.x, y: pos.y + v.y, z: pos.z + v.z)
                let p0 = project(pos), p1 = project(next)
                pos = next
                let dx = p1.x - p0.x, dy = p1.y - p0.y
                let len = (dx * dx + dy * dy).squareRoot()
                if len < 1e-9 { continue }                 // vector points straight at the camera

                var g = SplitMix64(seed: deriveSeed(seed, 0x1000_0000 &+ (UInt64(wi) << 16) &+ UInt64(ci)))
                let bend = g.range(-0.12, 0.12) * len
                let c = Pt((p0.x + p1.x) / 2 - dy / len * bend, (p0.y + p1.y) / 2 + dx / len * bend)
                let widthA = g.range(0.9, 1.5)
                let widthB = widthA * g.range(0.55, 0.85)

                var hx = p1.x - c.x, hy = p1.y - c.y
                let hl = (hx * hx + hy * hy).squareRoot()
                if hl < 1e-9 { hx = dx / len; hy = dy / len } else { hx /= hl; hy /= hl }
                let barbLen = len * g.range(0.16, 0.24)
                let th = g.range(18, 32) * .pi / 180
                let bx = -hx, by = -hy
                func rot(_ a: Double) -> Pt { Pt(bx * cos(a) - by * sin(a), bx * sin(a) + by * cos(a)) }
                let l = rot(th), r = rot(-th)
                strokes.append(WordArtStroke(
                    a: p0, c: c, b: p1,
                    barbL: Pt(p1.x + l.x * barbLen, p1.y + l.y * barbLen),
                    barbR: Pt(p1.x + r.x * barbLen, p1.y + r.y * barbLen),
                    widthA: widthA, widthB: widthB, tone: tone, wordIndex: wi))
            }
        }
        guard !strokes.isEmpty else { return .empty }

        // Fit the whole picture into the −0.5…0.5 square, preserving aspect.
        var pts: [Pt] = []
        for s in strokes { pts += [s.a, s.c, s.b] + [s.barbL, s.barbR].compactMap { $0 } }
        let minX = pts.map(\.x).min()!, maxX = pts.map(\.x).max()!
        let minY = pts.map(\.y).min()!, maxY = pts.map(\.y).max()!
        let extent = max(maxX - minX, maxY - minY)
        guard extent > 1e-9 else { return .empty }
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        func norm(_ p: Pt) -> Pt { Pt((p.x - cx) / extent, (p.y - cy) / extent) }
        strokes = strokes.map { s in
            var s = s
            s.a = norm(s.a); s.c = norm(s.c); s.b = norm(s.b)
            s.barbL = s.barbL.map(norm); s.barbR = s.barbR.map(norm)
            return s
        }

        let pl = placement(seed: seed)
        return WordArtDrawing(strokes: strokes, center: pl.center, size: pl.size, rotation: pl.rotation)
    }

    /// Where the doodle sits: anywhere on the page such that even a 25° rotation stays on it.
    /// Depends on the seed only, so the text can wrap around the same frame before a word is typed.
    public static func placement(seed: UInt64) -> WordArtPlacement {
        var pl = SplitMix64(seed: deriveSeed(seed, 22))
        let size = pl.range(0.26, 0.42)
        let rotation = pl.range(-25, 25)
        let hxm = 0.67 * size + 0.02
        let hym = 0.67 * size * pageWidthOverHeight + 0.02
        return WordArtPlacement(center: Pt(pl.range(hxm, 1 - hxm), pl.range(hym, 1 - hym)),
                                size: size, rotation: rotation)
    }
}
