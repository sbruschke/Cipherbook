import Foundation

public enum Paginator {
    /// Alternating runs of whitespace / non-whitespace, so breaks land between words.
    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var curIsSpace: Bool?
        for ch in s {
            let isSpace = ch.isWhitespace
            if let c = curIsSpace, c != isSpace { out.append(cur); cur = "" }
            cur.append(ch)
            curIsSpace = isSpace
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// Splits `text` into pages that each satisfy `fits`, greedily. `fits` must be monotone
    /// (a prefix of a fitting string fits). The pages always concatenate back to `text`.
    public static func paginate(_ text: String, fits: (String) -> Bool) -> [String] {
        var toks = tokens(text)
        if toks.isEmpty { return [""] }
        var pages: [String] = []
        var i = 0
        while i < toks.count {
            // Largest k such that toks[i..<i+k] fits.
            // Gallop (1, 2, 4 …) to an upper bound first, so the cost of a page depends on the
            // page, not on how much text follows it; then binary search inside the bracket.
            let remaining = toks.count - i
            var lo = 0, hi = remaining
            var step = 1
            while step < remaining {
                if fits(toks[i..<(i + step)].joined()) { lo = step; step *= 2 } else { hi = step - 1; break }
            }
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if fits(toks[i..<(i + mid)].joined()) { lo = mid } else { hi = mid - 1 }
            }
            if lo > 0 {
                pages.append(toks[i..<(i + lo)].joined())
                i += lo
                continue
            }
            // Even the first token is too big: cut it by characters (at least one).
            let chars = Array(toks[i])
            var cl = 0, ch = chars.count
            while cl < ch {
                let mid = (cl + ch + 1) / 2
                if fits(String(chars[0..<mid])) { cl = mid } else { ch = mid - 1 }
            }
            let take = max(1, cl)
            pages.append(String(chars[0..<take]))
            if take < chars.count {
                toks[i] = String(chars[take...])
            } else {
                i += 1
            }
        }
        return pages
    }
}

/// Scale (≤ 1) that makes `contentHeight` fit in `available`, never below `minimum`.
public func fitScale(contentHeight: Double, available: Double, minimum: Double = 0.7) -> Double {
    guard contentHeight > 0 else { return 1 }
    if contentHeight <= available { return 1 }
    return max(minimum, available / contentHeight)
}
