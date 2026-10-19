import Foundation

/// One sample of a page being shuffled. `layer` is a step function: it applies from this
/// keyframe's `t` until the next one. `lift` (0…1) drives the shadow.
public struct ShuffleKeyframe: Equatable {
    public var t: Double
    public var offsetX: Double
    public var layer: Int
    public var lift: Double
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
}
