import SwiftUI

// CALIBRATION (branch fx-lab only, never to be merged): the "comet" slot draws fxlab's calibration panels.
// JS twin: tools/fxlab/calibration/calib-flight.js. Panel D at t = 1/3, E at 2/3 (frames=4).
struct CometFlight: FlightEffectRenderer {
    let duration: Double = 0.9
    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) {
        if f.t < 0.5 { cmPanelD(f, ctx) } else { cmPanelE(f, ctx) }
    }
}

private func cmR(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
private func cmP(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
private func cmSolid(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> GraphicsContext.Shading { .color(RGBA(r, g, b, a).color) }

private func cmCross(_ ctx: GraphicsContext, _ p: CGPoint) {
    let c = Path { q in
        q.move(to: cmP(p.x - 6, p.y)); q.addLine(to: cmP(p.x + 6, p.y))
        q.move(to: cmP(p.x, p.y - 6)); q.addLine(to: cmP(p.x, p.y + 6))
    }
    ctx.stroke(c, with: cmSolid(1, 0.2, 0.2), lineWidth: 1)
}

private func cmLine(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> Path {
    Path { p in
        p.move(to: cmP(x0, y0))
        p.addLine(to: cmP(x1, y1))
    }
}

private func cmPanelD(_ f: FlightFrame, _ ctx: GraphicsContext) {
    let white = cmSolid(1, 1, 1)
    let caps: [CGLineCap] = [.butt, .round, .square]
    for i in 0..<3 {
        let y: CGFloat = 80 + CGFloat(i) * 30
        ctx.stroke(cmLine(60, y, 260, y), with: white, style: StrokeStyle(lineWidth: 12, lineCap: caps[i]))
    }
    let guides = Path { p in
        p.move(to: cmP(60, 60)); p.addLine(to: cmP(60, 160))
        p.move(to: cmP(260, 60)); p.addLine(to: cmP(260, 160))
    }
    ctx.stroke(guides, with: cmSolid(1, 0.2, 0.2), lineWidth: 1)
    let joins: [CGLineJoin] = [.miter, .round, .bevel]
    for i in 0..<3 {
        let x: CGFloat = 320 + CGFloat(i) * 150
        let z = Path { p in
            p.move(to: cmP(x, 170)); p.addLine(to: cmP(x + 40, 70))
            p.addLine(to: cmP(x + 80, 170)); p.addLine(to: cmP(x + 100, 80))
        }
        ctx.stroke(z, with: white, style: StrokeStyle(lineWidth: 12, lineJoin: joins[i]))
    }
    let sharp = Path { p in
        p.move(to: cmP(800, 170)); p.addLine(to: cmP(830, 70)); p.addLine(to: cmP(860, 170))
    }
    ctx.stroke(sharp, with: white, style: StrokeStyle(lineWidth: 10, lineJoin: .miter, miterLimit: 2))
    ctx.stroke(sharp.offsetBy(dx: 100, dy: 0), with: white, style: StrokeStyle(lineWidth: 10, lineJoin: .miter, miterLimit: 10))
    ctx.stroke(cmLine(60, 220, 460, 220), with: white, style: StrokeStyle(lineWidth: 6, dash: [20, 10]))
    ctx.stroke(cmLine(60, 240, 460, 240), with: white, style: StrokeStyle(lineWidth: 6, dash: [20, 10], dashPhase: 5))
    ctx.stroke(cmLine(60, 260, 460, 260), with: white, style: StrokeStyle(lineWidth: 8, lineCap: .round, dash: [0, 16]))
    ctx.stroke(cmLine(60, 280, 460, 280), with: white, style: StrokeStyle(lineWidth: 4, lineCap: .square, dash: [10, 10, 2, 10]))
    ctx.stroke(Path(cmR(520, 210, 120, 80)), with: white, style: StrokeStyle(lineWidth: 4, dash: [30, 10]))
    ctx.stroke(Path(ellipseIn: cmR(680, 210, 120, 80)), with: white, style: StrokeStyle(lineWidth: 4, dash: [30, 10]))
    ctx.stroke(Path(roundedRect: cmR(840, 210, 120, 80), cornerRadius: 20), with: white, style: StrokeStyle(lineWidth: 4, dash: [30, 10]))
    let starts: [Double] = [0, 0, -45, -45]
    let ends: [Double] = [90, 90, 200, 200]
    let clockwise: [Bool] = [false, true, false, true]
    for i in 0..<4 {
        let c = cmP(110 + CGFloat(i) * 160, 420)
        let wedge = Path { p in
            p.move(to: c)
            p.addArc(center: c, radius: 60, startAngle: .degrees(starts[i]), endAngle: .degrees(ends[i]), clockwise: clockwise[i])
            p.closeSubpath()
        }
        ctx.fill(wedge, with: cmSolid(0.3, 0.7, 1, 0.8))
        cmCross(ctx, cmP(c.x + 60, c.y))
    }
    let a1 = Path { p in
        p.addArc(center: cmP(760, 420), radius: 50, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
    }
    ctx.stroke(a1, with: white, lineWidth: 6)
    let a2 = Path { p in
        p.move(to: cmP(840, 360))
        p.addArc(center: cmP(950, 420), radius: 50, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
    }
    ctx.stroke(a2, with: white, lineWidth: 6)
    ctx.stroke(Path(ellipseIn: cmR(1040, 370, 100, 100)), with: cmSolid(1, 1, 1, 0.25), lineWidth: 6)
    ctx.stroke(Path(ellipseIn: cmR(1040, 370, 100, 100)).trimmedPath(from: 0.1, to: 0.4), with: cmSolid(1, 0.6, 0.1), lineWidth: 6)
    var g = ctx
    g.translateBy(x: 110, y: 600)
    g.rotate(by: .degrees(30))
    g.fill(Path(cmR(0, -5, 120, 10)), with: white)
    ctx.stroke(cmLine(110, 600, 260, 600), with: cmSolid(1, 0.2, 0.2), lineWidth: 1)
    var s = ctx
    s.translateBy(x: 320, y: 560)
    s.scaleBy(x: 3, y: 1)
    s.stroke(Path(ellipseIn: cmR(0, 0, 40, 80)), with: white, lineWidth: 4)
    let q = Path { p in
        p.move(to: cmP(520, 640))
        p.addQuadCurve(to: cmP(680, 640), control: cmP(600, 540))
    }
    ctx.stroke(q, with: white, lineWidth: 4)
    let cu = Path { p in
        p.move(to: cmP(720, 640))
        p.addCurve(to: cmP(920, 640), control1: cmP(760, 520), control2: cmP(880, 720))
    }
    ctx.stroke(cu, with: white, lineWidth: 4)
}

private func cmPanelE(_ f: FlightFrame, _ ctx: GraphicsContext) {
    let sizes: [CGFloat] = [9, 13, 20, 32, 56]
    var y: CGFloat = 90
    for s in sizes {
        let t = ctx.resolve(Text("Hxg 0123").font(.system(size: s)).foregroundColor(RGBA.white.color))
        ctx.draw(t, at: cmP(60, y), anchor: .leading)
        cmCross(ctx, cmP(60, y))
        y += s * 1.4 + 14
    }
    let anchors: [UnitPoint] = [.topLeading, .top, .topTrailing, .leading, .center, .trailing, .bottomLeading, .bottom, .bottomTrailing]
    for i in 0..<9 {
        let p = cmP(520 + CGFloat(i % 3) * 200, 120 + CGFloat(i / 3) * 90)
        let t = ctx.resolve(Text("Ag").font(.system(size: 28)).foregroundColor(RGBA.white.color))
        ctx.draw(t, at: p, anchor: anchors[i])
        cmCross(ctx, p)
    }
    let weights: [Font.Weight] = [.bold, .black, .light, .regular, .regular, .regular, .bold]
    let designs: [Font.Design] = [.default, .default, .default, .monospaced, .rounded, .serif, .monospaced]
    for i in 0..<7 {
        let font = Font.system(size: 22, weight: weights[i], design: designs[i])
        let t = ctx.resolve(Text("Things 0O1l").font(font).foregroundColor(RGBA.white.color))
        ctx.draw(t, at: cmP(60, 420 + CGFloat(i) * 40), anchor: .leading)
    }
    let boxed = ctx.resolve(Text("in rect").font(.system(size: 24)).foregroundColor(RGBA(1, 0.8, 0.3).color))
    ctx.stroke(Path(cmR(520, 420, 200, 60)), with: cmSolid(1, 0.2, 0.2), lineWidth: 1)
    ctx.draw(boxed, in: cmR(520, 420, 200, 60))
    var g = ctx
    g.opacity = 0.5
    g.translateBy(x: 820, y: 520)
    g.rotate(by: .degrees(-20))
    let tilted = ctx.resolve(Text("Tilted").font(.system(size: 30, weight: .bold)).foregroundColor(RGBA.white.color))
    g.draw(tilted, at: cmP(0, 0), anchor: .center)
    cmCross(ctx, cmP(820, 520))
    let jp = ctx.resolve(Text("ﾊﾟ日本").font(.system(size: 30, design: .monospaced)).foregroundColor(RGBA(0.4, 1, 0.5).color))
    ctx.draw(jp, at: cmP(820, 640), anchor: .center)
    cmCross(ctx, cmP(820, 640))
}
