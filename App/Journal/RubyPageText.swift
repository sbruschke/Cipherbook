import SwiftUI
import CoreText
import JournalCore

struct RubyPageText: UIViewRepresentable {
    var text: String
    var mainFont: UIFont
    var subFont: UIFont?
    var ink: UIColor
    var size: CGSize
    /// Text-box points (origin top-left); nil ⇒ text spans the full width.
    var exclusion: CGRect? = nil

    func makeUIView(context: Context) -> RubyView { let v = RubyView(); v.isOpaque = false; v.backgroundColor = .clear; return v }
    func updateUIView(_ v: RubyView, context: Context) {
        v.text = text; v.mainFont = mainFont; v.subFont = subFont; v.ink = ink; v.exclusion = exclusion; v.setNeedsDisplay()
    }

    static func attributed(_ text: String, main: UIFont, sub: UIFont?, ink: UIColor) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [.font: main, .foregroundColor: ink]
        guard let sub else { return NSAttributedString(string: text, attributes: base) }
        let out = NSMutableAttributedString()
        var cursor = text.startIndex
        for range in wordRanges(in: text) {
            if cursor < range.lowerBound { out.append(NSAttributedString(string: String(text[cursor..<range.lowerBound]), attributes: base)) }
            let word = String(text[range])
            var attrs = base
            let subAttrs: [CFString: Any] = [kCTFontAttributeName: sub, kCTForegroundColorAttributeName: ink.cgColor]
            attrs[NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)] =
                CTRubyAnnotationCreateWithAttributes(.center, .auto, .after, word as CFString, subAttrs as CFDictionary)
            out.append(NSAttributedString(string: word, attributes: attrs))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { out.append(NSAttributedString(string: String(text[cursor...]), attributes: base)) }
        return out
    }

    /// Runs of non-whitespace — the same notion of "word" the reader's sub font uses.
    static func wordRanges(in s: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []; var start: String.Index?
        for i in s.indices {
            if s[i].isWhitespace { if let st = start { out.append(st..<i); start = nil } }
            else if start == nil { start = i }
        }
        if let st = start { out.append(st..<s.endIndex) }
        return out
    }

    struct PlacedLine { let line: CTLine; let x: CGFloat; let baseline: CGFloat }   // baseline measured down from the top

    /// Lays the text out row by row. In each row the free segments (box minus `exclusion`) are filled
    /// left to right, so text reads across both sides of the doodle in order. A hard newline ends the row.
    static func layout(_ a: NSAttributedString, width: CGFloat, exclusion: CGRect?) -> (lines: [PlacedLine], height: CGFloat) {
        let ts = CTTypesetterCreateWithAttributedString(a)
        let length = a.length
        let ns = a.string as NSString
        let ex = exclusion.map { PageRect(minX: Double($0.minX), minY: Double($0.minY), maxX: Double($0.maxX), maxY: Double($0.maxY)) }
        var lines: [PlacedLine] = []
        var idx = 0, y: CGFloat = 0
        var guardRows = 0
        func metrics(_ l: CTLine) -> (asc: CGFloat, desc: CGFloat, lead: CGFloat) {
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            _ = CTLineGetTypographicBounds(l, &asc, &desc, &lead)
            return (asc, desc, lead)
        }
        while idx < length, guardRows < 10_000 {
            guardRows += 1
            // Probe the row height with a full-width line.
            let probeCount = max(1, CTTypesetterSuggestLineBreak(ts, idx, Double(width)))
            let m = metrics(CTTypesetterCreateLine(ts, CFRange(location: idx, length: probeCount)))
            var rowAsc = m.asc, rowDesc = m.desc + m.lead
            let segs = WrapGeometry.segments(top: Double(y), bottom: Double(y + rowAsc + rowDesc), width: Double(width),
                                             exclusion: ex, minSegment: Double(max(24, rowAsc * 2)))
            if segs.isEmpty {                      // the doodle fills this row: skip below it
                y = max(y + 1, CGFloat(ex?.maxY ?? Double(y) + 1)); continue
            }
            var rowLines: [(CTLine, CGFloat)] = []
            for seg in segs where idx < length {
                var n = CTTypesetterSuggestLineBreak(ts, idx, seg.upperBound - seg.lowerBound)
                if n <= 0 { n = 1 }
                let line = CTTypesetterCreateLine(ts, CFRange(location: idx, length: n))
                let lm = metrics(line)
                rowAsc = max(rowAsc, lm.asc); rowDesc = max(rowDesc, lm.desc + lm.lead)
                rowLines.append((line, CGFloat(seg.lowerBound)))
                let endsRow = ns.character(at: idx + n - 1) == 0x0A
                idx += n
                if endsRow { break }
            }
            for (l, x) in rowLines { lines.append(PlacedLine(line: l, x: x, baseline: y + rowAsc)) }
            y += rowAsc + rowDesc
        }
        return (lines, y)
    }

    /// Pagination predicate: does `text` fit one page at this size/fonts (and around `exclusion`)?
    static func fits(_ text: String, main: UIFont, sub: UIFont?, size: CGSize, exclusion: CGRect? = nil) -> Bool {
        layout(attributed(text, main: main, sub: sub, ink: .black), width: size.width, exclusion: exclusion).height <= size.height
    }

    final class RubyView: UIView {
        var text = "", ink = UIColor.black
        var mainFont = UIFont.systemFont(ofSize: 18)
        var subFont: UIFont?
        var exclusion: CGRect?

        override func draw(_ rect: CGRect) {
            guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 1, bounds.height > 1, !text.isEmpty else { return }
            let a = RubyPageText.attributed(text, main: mainFont, sub: subFont, ink: ink)
            let natural = RubyPageText.layout(a, width: bounds.width, exclusion: exclusion).height
            let scale = CGFloat(fitScale(contentHeight: Double(natural), available: Double(bounds.height)))
            // Overflow: shrink (≥ 70 %) by laying out in a proportionally larger box, then scaling down.
            let inv = 1 / scale
            let ex = exclusion.map { CGRect(x: $0.minX * inv, y: $0.minY * inv, width: $0.width * inv, height: $0.height * inv) }
            let laid = RubyPageText.layout(a, width: bounds.width * inv, exclusion: ex)
            ctx.saveGState()
            ctx.scaleBy(x: scale, y: scale)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)               // UIKit is y-down; CoreText is y-up
            for p in laid.lines {
                ctx.textPosition = CGPoint(x: p.x, y: p.baseline)
                CTLineDraw(p.line, ctx)
            }
            ctx.restoreGState()
        }
    }
}
