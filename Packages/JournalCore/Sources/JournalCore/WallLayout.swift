import Foundation

public struct Cell: Hashable { public var col: Int; public var row: Int }

public enum WallLayout {
    public static let cellW = 260.0
    public static let cellH = 340.0

    public static func cell(for p: Pt) -> Cell {
        Cell(col: Int((p.x / cellW).rounded()), row: Int((p.y / cellH).rounded()))
    }

    public static func center(of c: Cell) -> Pt { Pt(Double(c.col) * cellW, Double(c.row) * cellH) }

    /// Nearest unoccupied cell to the exact point `p`, searching outward ring by ring.
    static func nearestFree(to p: Pt, occupied: Set<Cell>) -> Cell {
        let home = cell(for: p)
        if !occupied.contains(home) { return home }
        var best: (Cell, Double)?
        for ring in 1...64 {
            for row in (home.row - ring)...(home.row + ring) {
                for col in (home.col - ring)...(home.col + ring) {
                    guard max(abs(col - home.col), abs(row - home.row)) == ring else { continue }
                    let c = Cell(col: col, row: row)
                    if occupied.contains(c) { continue }
                    let ctr = center(of: c)
                    let d = (ctr.x - p.x) * (ctr.x - p.x) + (ctr.y - p.y) * (ctr.y - p.y)
                    if best == nil || d < best!.1 { best = (c, d) }     // row-major scan ⇒ stable ties
                }
            }
            if best != nil { return best!.0 }
        }
        return home
    }

    public static func snapAll(_ entries: [Entry]) -> [Entry] {
        var out = entries
        let order = entries.indices.filter { !entries[$0].deleted }
            .sorted { (entries[$0].createdAt, entries[$0].id) < (entries[$1].createdAt, entries[$1].id) }
        var occupied = Set<Cell>()
        for i in order {
            let p = Pt(entries[i].x, entries[i].y)
            let c = nearestFree(to: p, occupied: occupied)
            occupied.insert(c)
            let ctr = center(of: c)
            if out[i].freeX == nil { out[i].freeX = p.x; out[i].freeY = p.y }
            out[i].x = ctr.x; out[i].y = ctr.y
        }
        return out
    }

    public static func restoreAll(_ entries: [Entry]) -> [Entry] {
        entries.map { e in
            var e = e
            guard !e.deleted, let fx = e.freeX, let fy = e.freeY else { return e }
            e.x = fx; e.y = fy; e.freeX = nil; e.freeY = nil
            return e
        }
    }

    public static func drop(_ id: String, at p: Pt, snap: Bool, in entries: [Entry]) -> [Entry] {
        var out = entries
        guard let i = out.firstIndex(where: { $0.id == id && !$0.deleted }) else { return out }
        if snap {
            let occupied = Set(out.enumerated().filter { $0.offset != i && !$0.element.deleted }
                .map { cell(for: Pt($0.element.x, $0.element.y)) })
            let ctr = center(of: nearestFree(to: p, occupied: occupied))
            out[i].x = ctr.x; out[i].y = ctr.y
        } else {
            out[i].x = p.x; out[i].y = p.y
        }
        out[i].freeX = nil; out[i].freeY = nil
        return out
    }
}
