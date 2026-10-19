import Foundation

public enum WrapGeometry {
    public static func segments(top: Double, bottom: Double, width: Double, exclusion: PageRect?,
                                minSegment: Double) -> [ClosedRange<Double>] {
        guard let e = exclusion, bottom > e.minY, top < e.maxY else { return width > 0 ? [0...width] : [] }
        var out: [ClosedRange<Double>] = []
        let leftEnd = min(width, max(0, e.minX)), rightStart = max(0, min(width, e.maxX))
        if leftEnd - 0 >= minSegment { out.append(0...leftEnd) }
        if width - rightStart >= minSegment { out.append(rightStart...width) }
        return out
    }
}
