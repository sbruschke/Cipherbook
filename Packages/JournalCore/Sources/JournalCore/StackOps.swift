import Foundation

/// One sample of a page being shuffled. `layer` is a step function: it applies from this
/// keyframe's `t` until the next one. `lift` (0…1) drives the shadow.
public struct ShuffleKeyframe: Equatable {
    public var t: Double
    public var offsetX: Double
    public var layer: Int
    public var lift: Double

    public init(t: Double, offsetX: Double, layer: Int, lift: Double) {
        self.t = t; self.offsetX = offsetX; self.layer = layer; self.lift = lift
    }
}

public enum StackOps {
    /// `pages` bottom → top. Returns the same pages with `order` renumbered 0…n-1.
    public static func move(_ pages: [Page], from: Int, to: Int) -> [Page] {
        var list = pages.sorted { $0.order < $1.order }
        guard list.indices.contains(from), list.indices.contains(to), from != to else { return list }
        let p = list.remove(at: from)
        list.insert(p, at: to)
        for i in list.indices { list[i].order = i }
        return list
    }

    /// A page leaves the stack sideways *beneath* the pages above it, rises clear, changes layer
    /// only while fully outside the stack (`offsetX >= clearance`), then slides back in at its
    /// new layer. That is the physical rule: it never passes through pages it should be behind.
    public static func shufflePath(count: Int, from: Int, to: Int, clearance: Double) -> [ShuffleKeyframe] {
        guard count > 1, from != to, (0..<count).contains(from), (0..<count).contains(to) else { return [] }
        return [
            ShuffleKeyframe(t: 0.00, offsetX: 0,         layer: from, lift: 0),
            ShuffleKeyframe(t: 0.30, offsetX: clearance, layer: from, lift: 0),
            ShuffleKeyframe(t: 0.45, offsetX: clearance, layer: to,   lift: 1),
            ShuffleKeyframe(t: 0.60, offsetX: clearance, layer: to,   lift: 1),
            ShuffleKeyframe(t: 0.75, offsetX: clearance, layer: to,   lift: 0),
            ShuffleKeyframe(t: 1.00, offsetX: 0,         layer: to,   lift: 0),
        ]
    }

    /// The page's state at progress `t` (0…1): offset and lift interpolate linearly between the two
    /// surrounding keyframes; the layer is the earlier keyframe's (it steps, it never blends).
    public static func sample(_ path: [ShuffleKeyframe], at t: Double) -> ShuffleKeyframe {
        guard let first = path.first, let last = path.last else {
            return ShuffleKeyframe(t: 0, offsetX: 0, layer: 0, lift: 0)
        }
        if t <= first.t { return first }
        if t >= last.t { return last }
        let i = path.lastIndex(where: { $0.t <= t })!
        let a = path[i], b = path[i + 1]
        let f = (t - a.t) / (b.t - a.t)
        return ShuffleKeyframe(t: t, offsetX: a.offsetX + (b.offsetX - a.offsetX) * f,
                               layer: a.layer, lift: a.lift + (b.lift - a.lift) * f)
    }
}
