import SwiftUI

// CALIBRATION (branch fx-lab only, never to be merged): the "tv" slot draws fxlab's calibration panels.
// JS twin: tools/fxlab/calibration/calib-close.js. Panel A at t = 0, B at 1/3, C at 2/3 (frames=4).
struct TVClose: CloseEffectRenderer {
    let duration: Double = 0.8

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        if f.t < 0.2 { tvPanelA(f, ctx) } else if f.t < 0.5 { tvPanelB(f, ctx) } else { tvPanelC(f, ctx) }
    }
}

private func tvR(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
private func tvP(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
private func tvSolid(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> GraphicsContext.Shading { .color(RGBA(r, g, b, a).color) }
private func tvStop(_ c: RGBA, _ l: CGFloat) -> Gradient.Stop { Gradient.Stop(color: c.color, location: l) }

private func tvPanelA(_ f: CloseFrame, _ ctx: GraphicsContext) {
    f.drawPad(ctx, in: f.pad, opacity: 1)
    let modes: [GraphicsContext.BlendMode] = [.plusLighter, .screen, .multiply, .destinationOut]
    for i in 0..<4 {
        var g = ctx
        g.blendMode = modes[i]
        let x: CGFloat = 190 + CGFloat(i) * 110
        g.fill(Path(tvR(x, 120, 70, 70)), with: tvSolid(0.2, 0.6, 0.9, 0.8))
        g.fill(Path(tvR(x, 330, 70, 70)), with: tvSolid(0.2, 0.6, 0.9, 0.8))
    }
    let conic = Gradient(stops: [tvStop(RGBA(1, 0, 0), 0), tvStop(RGBA(0, 1, 0), 0.25), tvStop(RGBA(0, 0, 1), 0.5),
                                 tvStop(RGBA(1, 1, 1), 0.75), tvStop(RGBA(0, 0, 0), 1)])
    ctx.fill(Path(ellipseIn: tvR(20, 20, 120, 120)), with: .conicGradient(conic, center: tvP(80, 80), angle: .degrees(30)))
    let lin = Gradient(stops: [tvStop(RGBA(1, 0, 0), 0.2), tvStop(RGBA(0, 0, 1), 0.8)])
    ctx.fill(Path(tvR(10, 160, 140, 40)), with: .linearGradient(lin, startPoint: tvP(40, 180), endPoint: tvP(120, 180)))
    let rad = Gradient(stops: [tvStop(RGBA(1, 1, 0), 0), tvStop(RGBA(1, 0, 0), 0.5), tvStop(RGBA(1, 0, 0, 0), 1)])
    ctx.fill(Path(tvR(20, 220, 120, 120)), with: .radialGradient(rad, center: tvP(80, 280), startRadius: 15, endRadius: 55))
    let hard = Gradient(stops: [tvStop(RGBA(0, 1, 0), 0), tvStop(RGBA(0, 1, 0), 0.5), tvStop(RGBA(0.6, 0, 1), 0.5),
                                tvStop(RGBA(0.6, 0, 1), 1)])
    ctx.fill(Path(tvR(680, 20, 120, 40)), with: .linearGradient(hard, startPoint: tvP(680, 0), endPoint: tvP(800, 0)))
    let unsorted = Gradient(stops: [tvStop(RGBA(1, 0, 0), 0.8), tvStop(RGBA(0, 0, 1), 0.2)])
    ctx.fill(Path(tvR(680, 80, 120, 40)), with: .linearGradient(unsorted, startPoint: tvP(680, 0), endPoint: tvP(800, 0)))
    let three = Gradient(colors: [RGBA(1, 1, 1).color, RGBA(1, 0.5, 0).color, RGBA(0, 0, 0, 0).color])
    ctx.fill(Path(tvR(680, 140, 120, 120)), with: .linearGradient(three, startPoint: tvP(0, 140), endPoint: tvP(0, 260)))
    var g2 = ctx
    g2.translateBy(x: 740, y: 360)
    g2.rotate(by: .degrees(45))
    g2.scaleBy(x: 1, y: 0.5)
    g2.fill(Path(ellipseIn: tvR(-50, -50, 100, 100)), with: .conicGradient(conic, center: tvP(0, 0), angle: .degrees(0)))
}

private func tvPanelB(_ f: CloseFrame, _ ctx: GraphicsContext) {
    let white = tvSolid(1, 1, 1)
    var s1 = ctx
    s1.addFilter(.shadow(color: RGBA(1, 0, 0, 1).color, radius: 8, x: 12, y: 10))
    s1.fill(Path(tvR(30, 30, 60, 60)), with: white)
    var s2 = ctx
    s2.addFilter(.shadow(color: RGBA(1, 0, 0, 1).color, radius: 8, x: 12, y: 10, options: .shadowOnly))
    s2.fill(Path(tvR(140, 30, 60, 60)), with: white)
    var s3 = ctx
    s3.addFilter(.shadow(color: RGBA(0, 1, 0, 1).color, radius: 3, x: -10, y: 0))
    s3.addFilter(.shadow(color: RGBA(0, 0, 1, 1).color, radius: 3, x: 0, y: 14))
    s3.fill(Path(tvR(250, 30, 60, 60)), with: white)
    var b1 = ctx
    b1.addFilter(.blur(radius: 4))
    b1.fill(Path(tvR(370, 40, 40, 40)), with: white)
    var b2 = ctx
    b2.translateBy(x: 450, y: 30)
    b2.scaleBy(x: 3, y: 3)
    b2.addFilter(.blur(radius: 4))
    b2.fill(Path(tvR(0, 0, 20, 20)), with: white)
    var b3 = ctx
    b3.addFilter(.blur(radius: 4))
    b3.translateBy(x: 580, y: 30)
    b3.scaleBy(x: 3, y: 3)
    b3.fill(Path(tvR(0, 0, 20, 20)), with: white)
    var b4 = ctx
    b4.addFilter(.blur(radius: 2))
    b4.stroke(Path(ellipseIn: tvR(700, 30, 80, 80)), with: white, lineWidth: 2)
    var m1 = ctx
    m1.addFilter(.alphaThreshold(min: 0.5, max: 1, color: RGBA(0.2, 0.8, 0.4).color))
    m1.drawLayer { l in
        l.addFilter(.blur(radius: 10))
        for i in 0..<5 {
            let x: CGFloat = 30 + CGFloat(i) * 50
            let y: CGFloat = 170 + CGFloat(i % 2) * 30
            l.fill(Path(ellipseIn: tvR(x, y, 50, 50)), with: white)
        }
    }
    var m2 = ctx
    m2.addFilter(.alphaThreshold(min: 0.2, max: 0.6, color: RGBA(1, 0.8, 0.2).color))
    m2.drawLayer { l in
        l.addFilter(.blur(radius: 10))
        l.fill(Path(ellipseIn: tvR(340, 170, 80, 80)), with: white)
    }
    var rb = ColorMatrix()
    rb.r1 = 0; rb.r3 = 1
    rb.b1 = 1; rb.b3 = 0
    var c1 = ctx
    c1.addFilter(.colorMatrix(rb))
    c1.fill(Path(tvR(460, 170, 60, 60)), with: tvSolid(1, 0.5, 0))
    var offset = ColorMatrix()
    offset.r5 = 0.5
    var c2 = ctx
    c2.addFilter(.colorMatrix(offset))
    c2.fill(Path(tvR(540, 170, 60, 60)), with: tvSolid(0, 0, 0, 0.5))
    let rainbow = Gradient(colors: [RGBA(1, 0, 0).color, RGBA(1, 1, 0).color, RGBA(0, 1, 0).color, RGBA(0, 1, 1).color,
                                    RGBA(0, 0, 1).color, RGBA(1, 0, 1).color])
    let filters: [GraphicsContext.Filter?] = [nil, .brightness(0.3), .contrast(0.5), .saturation(0.3), .hueRotation(.degrees(90)),
                                              .grayscale(1), .colorInvert(1), .colorMultiply(RGBA(0.5, 1, 1).color)]
    for i in 0..<filters.count {
        var g = ctx
        if let flt = filters[i] { g.addFilter(flt) }
        let y: CGFloat = 270 + CGFloat(i) * 22
        g.fill(Path(tvR(30, y, 300, 18)), with: .linearGradient(rainbow, startPoint: tvP(30, 0), endPoint: tvP(330, 0)))
        g.fill(Path(tvR(340, y, 60, 18)), with: tvSolid(0.5, 0.5, 0.5))
    }
    var o1 = ctx
    o1.opacity = 0.5
    o1.addFilter(.shadow(color: RGBA(0, 0, 0, 1).color, radius: 6, x: 8, y: 8))
    o1.fill(Path(tvR(460, 300, 80, 80)), with: white)
}

private func tvPanelC(_ f: CloseFrame, _ ctx: GraphicsContext) {
    f.drawPad(ctx, in: f.pad, opacity: 1)
    let red = tvSolid(1, 0, 0)
    var l1 = ctx
    l1.opacity = 0.5
    l1.drawLayer { l in
        l.fill(Path(tvR(10, 10, 60, 60)), with: red)
        l.fill(Path(tvR(40, 40, 60, 60)), with: red)
    }
    var l1b = ctx
    l1b.opacity = 0.5
    l1b.fill(Path(tvR(10, 110, 60, 60)), with: red)
    l1b.fill(Path(tvR(40, 140, 60, 60)), with: red)
    var l2 = ctx
    l2.translateBy(x: 20, y: 220)
    l2.scaleBy(x: 1.5, y: 1.5)
    l2.drawLayer { l in l.fill(Path(tvR(0, 0, 40, 40)), with: tvSolid(0, 1, 0)) }
    var l3 = ctx
    l3.blendMode = .plusLighter
    l3.drawLayer { l in
        l.fill(Path(tvR(190, 20, 80, 80)), with: tvSolid(0.4, 0.4, 0.4))
        l.fill(Path(tvR(230, 60, 80, 80)), with: tvSolid(0.4, 0.4, 0.4))
    }
    var l4 = ctx
    l4.addFilter(.blur(radius: 3))
    l4.drawLayer { l in l.fill(Path(tvR(350, 30, 60, 60)), with: tvSolid(1, 1, 1)) }
    var l5 = ctx
    l5.clip(to: Path(ellipseIn: tvR(440, 20, 90, 90)))
    l5.drawLayer { l in l.fill(Path(tvR(420, 0, 130, 130)), with: tvSolid(1, 0.5, 0)) }
    ctx.drawLayer { l in
        l.fill(Path(tvR(550, 20, 100, 100)), with: tvSolid(1, 1, 1))
        l.blendMode = .destinationOut
        l.fill(Path(ellipseIn: tvR(575, 45, 50, 50)), with: tvSolid(0, 0, 0))
    }
    var l7 = ctx
    l7.blendMode = .destinationOut
    l7.fill(Path(ellipseIn: tvR(575, 160, 50, 50)), with: tvSolid(0, 0, 0))
    var c1 = ctx
    c1.clip(to: Path(ellipseIn: tvR(50, 320, 80, 80)), options: .inverse)
    c1.fill(Path(tvR(20, 300, 140, 120)), with: tvSolid(0.2, 0.4, 1))
    var c2 = ctx
    c2.clip(to: Path(tvR(200, 300, 120, 120)))
    c2.clip(to: Path(ellipseIn: tvR(230, 330, 60, 60)), options: .inverse)
    c2.fill(Path(tvR(180, 290, 160, 160)), with: tvSolid(0.2, 1, 0.6))
    let ring = Path { p in
        p.addEllipse(in: tvR(360, 300, 120, 120))
        p.addEllipse(in: tvR(390, 330, 60, 60))
    }
    var c3 = ctx
    c3.clip(to: ring, style: FillStyle(eoFill: true))
    c3.fill(Path(tvR(350, 290, 140, 140)), with: tvSolid(1, 0.9, 0.2))
    var c4 = ctx
    c4.clipToLayer(opacity: 0.5) { l in l.fill(Path(ellipseIn: tvR(510, 310, 100, 100)), with: tvSolid(1, 1, 1)) }
    c4.fill(Path(tvR(500, 300, 120, 120)), with: tvSolid(1, 0.3, 0.8))
    var c5 = ctx
    c5.clip(to: Path(tvR(660, 300, 80, 80)))
    c5.translateBy(x: 40, y: 40)
    c5.fill(Path(tvR(660, 300, 80, 80)), with: tvSolid(0.6, 0.6, 1))
    ctx.drawLayer { l in
        l.clip(to: Path(ellipseIn: tvR(680, 20, 120, 120)), options: .inverse)
        l.fill(Path(tvR(690, 30, 100, 100)), with: tvSolid(0.5, 1, 1))
    }
}
