import Foundation

public struct Point: Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    func distance(to other: Point) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// Turns a finger path over the letter keys into words.
///
/// Candidates come from the lexicon's first/last-letter buckets for the keys near the
/// path's two ends, are pruned by requiring the path to pass near each of the word's
/// keys in order, and are scored by how far the path strays from the word's ideal
/// key-to-key path, combined with the language model.
public struct SwipeDecoder {
    public let predictor: Predictor
    /// Points each path is resampled to before comparison.
    public var samples = 40
    /// Cost, in log-probability units, of one key-width of mean deviation between the
    /// path and the word's ideal path when both are resampled and compared point by point.
    public var shapeWeight = 9.0
    /// Cost of the path's mean distance from the word's key-to-key polyline. Catches
    /// words whose ideal path is similar overall but misses a corner the finger made.
    public var locationWeight = 6.0
    /// Cost of the path's start and end missing the word's first and last keys; people
    /// begin and finish a swipe far more precisely than they draw the middle.
    public var endpointWeight = 4.0
    /// Keys within this many key widths of a path end are tried as the word's end letters.
    public var endpointRadius = 1.05
    /// A word's keys must each come within this many key widths of the path, in order.
    public var passRadius = 1.25

    public init(predictor: Predictor) {
        self.predictor = predictor
    }

    /// Keys are the centres of the a–z letter keys, keyed by lowercase letter.
    /// Returns up to `limit` words, best first, or nothing if the path is a tap.
    public func decode(path: [Point], keys: [Character: Point], keyWidth: Double,
                       context: WordContext, limit: Int) -> [String] {
        guard path.count >= 2, keyWidth > 0, arcLength(path) >= keyWidth * 0.5 else { return [] }
        let lexicon = predictor.lexicon
        var centres = [Point?](repeating: nil, count: 26)
        for (letter, point) in keys {
            guard let ascii = letter.asciiValue, (0x61...0x7A).contains(ascii) else { continue }
            centres[Int(ascii - 0x61)] = point
        }

        let resampled = resample(path, to: samples)
        let firsts = nearbyKeys(resampled[0], centres, within: endpointRadius * keyWidth)
        let lasts = nearbyKeys(resampled[resampled.count - 1], centres, within: endpointRadius * keyWidth)

        var scored: [(word: String, cost: Double)] = []
        for first in firsts {
            for last in lasts {
                for id32 in lexicon.words(from: first, to: last) {
                    let id = Int(id32)
                    let letters = lexicon.swipeKeys(id)
                    guard let ideal = idealPath(letters, centres),
                          passesNear(resampled, ideal, radius: passRadius * keyWidth) else { continue }
                    let deviation = meanDistance(resampled, resample(ideal, to: samples)) / keyWidth
                    let offLine = meanDistance(resampled, toPolyline: ideal) / keyWidth
                    let ends = (resampled[0].distance(to: ideal[0])
                                + resampled[resampled.count - 1].distance(to: ideal[ideal.count - 1])) / keyWidth
                    let cost = shapeWeight * deviation + locationWeight * offLine + endpointWeight * ends
                        - Double(predictor.score(id, context: context))
                    scored.append((lexicon.word(id), cost))
                }
            }
        }
        scored.sort { $0.cost < $1.cost }
        var out: [String] = []
        for candidate in scored where !out.contains(candidate.word) {
            out.append(candidate.word)
            if out.count == limit { break }
        }
        return out
    }

    // MARK: Geometry

    private func nearbyKeys(_ point: Point, _ centres: [Point?], within radius: Double) -> [UInt8] {
        var hits: [(key: UInt8, d: Double)] = []
        for (i, c) in centres.enumerated() {
            guard let c else { continue }
            hits.append((UInt8(0x61 + i), point.distance(to: c)))
        }
        hits.sort { $0.d < $1.d }
        // Always the nearest key, plus any others close enough to be what was meant.
        return hits.enumerated().filter { $0.offset == 0 || $0.element.d <= radius }.map(\.element.key)
    }

    /// The key centres a word's swipe passes through; nil if a key isn't on the layout.
    private func idealPath(_ letters: [UInt8], _ centres: [Point?]) -> [Point]? {
        var points: [Point] = []
        for l in letters {
            guard let c = centres[Int(l - 0x61)] else { return nil }
            points.append(c)
        }
        return points
    }

    /// Walks the path once, requiring each key to be passed near in turn.
    private func passesNear(_ path: [Point], _ keys: [Point], radius: Double) -> Bool {
        var i = 0
        for key in keys {
            while i < path.count, path[i].distance(to: key) > radius { i += 1 }
            if i == path.count { return false }
        }
        return true
    }

    private func arcLength(_ path: [Point]) -> Double {
        zip(path, path.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    private func meanDistance(_ a: [Point], _ b: [Point]) -> Double {
        zip(a, b).reduce(0) { $0 + $1.0.distance(to: $1.1) } / Double(min(a.count, b.count))
    }

    private func meanDistance(_ points: [Point], toPolyline line: [Point]) -> Double {
        var total = 0.0
        for p in points {
            var best = p.distance(to: line[0])
            for (a, b) in zip(line, line.dropFirst()) { best = min(best, distance(p, a, b)) }
            total += best
        }
        return total / Double(points.count)
    }

    /// Distance from `p` to the segment `a`–`b`.
    private func distance(_ p: Point, _ a: Point, _ b: Point) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return p.distance(to: Point(x: a.x + t * dx, y: a.y + t * dy))
    }

    /// `count` points evenly spaced along the polyline.
    func resample(_ path: [Point], to count: Int) -> [Point] {
        guard let first = path.first else { return [] }
        let total = arcLength(path)
        guard path.count > 1, total > 0 else { return Array(repeating: first, count: count) }
        let step = total / Double(count - 1)
        var out = [first]
        var carried = 0.0
        for (a, b) in zip(path, path.dropFirst()) {
            let segment = a.distance(to: b)
            guard segment > 0 else { continue }
            var along = step - carried
            while along <= segment, out.count < count {
                let t = along / segment
                out.append(Point(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                along += step
            }
            carried = segment - (along - step)
        }
        while out.count < count { out.append(path[path.count - 1]) }
        return out
    }
}
