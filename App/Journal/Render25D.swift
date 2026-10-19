import SwiftUI
import JournalCore

struct Render25D: WallRenderer {
    func page(_ s: PageRenderSpec) -> AnyView { AnyView(ParchmentPage(spec: s)) }
    func fastener(_ s: FastenerRenderSpec) -> AnyView { AnyView(FastenerShape(spec: s)) }
}

private func smoothPath(_ pts: [Pt], in size: CGSize) -> Path {
    var path = Path()
    guard pts.count > 2 else { return path }
    let p = pts.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
    let mid = { (a: CGPoint, b: CGPoint) in CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    path.move(to: mid(p[p.count - 1], p[0]))
    for i in 0..<p.count { path.addQuadCurve(to: mid(p[i], p[(i + 1) % p.count]), control: p[i]) }
    path.closeSubpath()
    return path
}

private func shade(_ hex: String, by delta: Double) -> Color {
    let ui = UIColor(Color(hex: hex))
    var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
    return Color(hue: Double(h), saturation: Double(sat), brightness: min(1, max(0, Double(b) + delta)))
}

struct ParchmentPage: View {
    let spec: PageRenderSpec

    var body: some View {
        let w = spec.size.width * spec.look.widthScale, h = spec.size.height
        let size = CGSize(width: w, height: h)
        let base = shade(spec.style.baseHex, by: spec.look.brightness)
        let edge = Color(hex: spec.style.edgeHex)
        ZStack {
            Canvas { ctx, sz in
                let outline = smoothPath(spec.look.outline, in: sz)
                ctx.fill(outline, with: .linearGradient(
                    Gradient(colors: [base, shade(spec.style.baseHex, by: spec.look.brightness - 0.05)]),
                    startPoint: .zero, endPoint: CGPoint(x: sz.width, y: sz.height)))
                ctx.clip(to: outline)
                for st in spec.look.stains {
                    let c = CGPoint(x: st.center.x * sz.width, y: st.center.y * sz.height)
                    let r = st.radius * sz.width
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                             with: .radialGradient(Gradient(colors: [edge.opacity(st.opacity), edge.opacity(0)]),
                                                   center: c, startRadius: 0, endRadius: r))
                }
                for cr in spec.look.creases {
                    var p = Path()
                    let a = CGPoint(x: cr.a.x * sz.width, y: cr.a.y * sz.height)
                    let b = CGPoint(x: cr.b.x * sz.width, y: cr.b.y * sz.height)
                    p.move(to: a)
                    p.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2 + cr.bend * sz.width,
                                                           y: (a.y + b.y) / 2 + cr.bend * sz.height))
                    ctx.stroke(p, with: .color(edge.opacity(cr.opacity)), lineWidth: 0.8)
                }
                for sp in spec.look.speckles {
                    let r = sp.radius * sz.width
                    ctx.fill(Path(ellipseIn: CGRect(x: sp.at.x * sz.width - r, y: sp.at.y * sz.height - r,
                                                    width: r * 2, height: r * 2)),
                             with: .color(edge.opacity(sp.opacity)))
                }
                if let art = spec.art, !art.isEmpty {
                    let inkUI = UIColor(spec.ink), accentUI = UIColor(spec.artColor)
                    func pt(_ p: Pt) -> CGPoint {
                        let q = art.pagePoint(p); return CGPoint(x: q.x * sz.width, y: q.y * sz.height)
                    }
                    for s in art.strokes {
                        // Early words are inked in the accent colour, later ones drift toward the writing ink
                        // (the original's red→black ramp), denser as the page goes on.
                        let color = Color(uiColor: accentUI.mix(inkUI, s.tone))
                            .opacity((0.28 + 0.4 * s.tone) * spec.artStrength)
                        var p = Path()
                        p.move(to: pt(s.a)); p.addQuadCurve(to: pt(s.b), control: pt(s.c))
                        ctx.stroke(p, with: .color(color),
                                   style: StrokeStyle(lineWidth: (s.widthA + s.widthB) * 0.55, lineCap: .round, lineJoin: .round))
                    }
                }
                // Darker rim, like old paper edges.
                ctx.stroke(outline, with: .color(edge.opacity(0.55)), lineWidth: 2.2)
            }
            .frame(width: w, height: h)

            RubyPageText(text: spec.text, mainFont: spec.mainFont, subFont: spec.subFont,
                         ink: UIColor(spec.ink), size: CGSize(width: w * 0.84, height: h * 0.86),
                         exclusion: spec.exclusion.map {
                             CGRect(x: $0.minX * w - 0.08 * w, y: $0.minY * h - 0.07 * h,
                                    width: ($0.maxX - $0.minX) * w, height: ($0.maxY - $0.minY) * h)
                         })
                .frame(width: w * 0.84, height: h * 0.86)
        }
        .frame(width: w, height: h)
        .rotationEffect(.degrees(spec.look.rotation))
        .shadow(color: .black.opacity(0.28 + 0.12 * spec.lift), radius: 2 + spec.lift * 14, x: 0, y: 1 + spec.lift * 9)
    }
}

private extension UIColor {
    func mix(_ other: UIColor, _ t: Double) -> UIColor {
        var a: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0), b: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        getRed(&a.0, green: &a.1, blue: &a.2, alpha: &a.3)
        other.getRed(&b.0, green: &b.1, blue: &b.2, alpha: &b.3)
        let t = CGFloat(t)
        return UIColor(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t, alpha: 1)
    }
}

struct FastenerShape: View {
    let spec: FastenerRenderSpec
    var body: some View {
        let w = spec.pageSize.width, h = spec.pageSize.height
        let x = spec.look.position.x * w, y = spec.look.position.y * h
        Group {
            switch spec.kind {
            case .pin:
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(hex: "#d8d2c4"), Color(hex: "#6b6558")],
                                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
                        .frame(width: 18 * spec.look.size, height: 18 * spec.look.size)
                    Circle().fill(.white.opacity(0.55)).frame(width: 5, height: 5).offset(x: -3, y: -3)
                }
                .shadow(color: .black.opacity(0.45), radius: 3, x: 2, y: 4)
            case .staple:
                RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: "#9aa0a6"))
                    .frame(width: 26 * spec.look.size, height: 4)
                    .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(.black.opacity(0.35), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.4), radius: 1.5, x: 1, y: 2)
            case .tape:
                Rectangle().fill(Color(hex: "#e8dfb8").opacity(0.72))
                    .frame(width: 70 * spec.look.size, height: 22)
                    .overlay(Rectangle().stroke(.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.18), radius: 1.2, y: 1)
            }
        }
        .rotationEffect(.degrees(spec.look.angle))
        .position(x: x, y: y)
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }
}
