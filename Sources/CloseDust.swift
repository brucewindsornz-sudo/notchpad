import SwiftUI

struct DustClose: CloseEffectRenderer {
    let duration: Double = 1.04

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let t: Double = f.t
        if t <= 0 { f.drawPad(ctx); return }
        if t >= 1 { return }

        let mist = f.dark ? RGBA(0.70, 0.73, 0.76) : RGBA(0.28, 0.26, 0.23)
        let rim = f.accent.mix(mist, 0.66)
        let sweep: Double = smoothstep(0.004, 0.74, t)
        if t < 0.74 { dustEdge(f, ctx, mist, rim, sweep) }
        dustClouds(f, ctx, mist)
        dustScatter(f, ctx, mist, sweep)

        let arrive: Double = smoothstep(0.79, 0.91, t)
        let settle: Double = arrive * (1 - smoothstep(0.91, 0.985, t))
        if settle > 0 {
            let pt = f.target
            let r: Double = 9 - 5 * phase(t, 0.79, 0.985)
            let g = Gradient(colors: [rim.alpha(0.26 * settle).color, rim.alpha(0).color])
            let rect = CGRect(x: Double(pt.x) - r, y: Double(pt.y) - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(g, center: pt, startRadius: 0, endRadius: r))
        }
    }
}

private func dustRag(_ v: Double, _ f: CloseFrame) -> Double {
    let folds: Double = 53 * (closeNoise(1.5, v * 5.2, f.seed) - 0.5)
    let tears: Double = 23 * (closeNoise(2.9, v * 16, f.seed ^ 0xDA57) - 0.5)
    let grains: Double = 14 * (closeNoise(4.7, v * 53, f.seed ^ 0x9BA7) - 0.5)
    return folds + tears + grains
}

private func dustFront(_ v: Double, _ f: CloseFrame, _ sweep: Double) -> Double {
    let width: Double = Double(f.pad.width)
    let diagonal: Double = 0.31 * width * (1 - v)
    let x: Double = Double(f.pad.maxX) + 24 + diagonal
    return x + dustRag(v, f) - sweep * (1.31 * width + 68)
}

// Leave the unbroken part of the actual picture in place, with short glints
// on selected folds of the torn edge rather than a solid luminous line.
private func dustEdge(_ f: CloseFrame, _ ctx: GraphicsContext, _ mist: RGBA, _ rim: RGBA, _ sweep: Double) {
    let pad = f.pad
    let height: Double = Double(pad.height)
    let count = max(16, Int((height / 3.5).rounded(.up)))
    var hull = Path()
    var crust = Path()
    var filigree = Path()
    hull.move(to: CGPoint(x: pad.minX - 4, y: pad.minY - 1))
    for i in 0...count {
        let v: Double = Double(i) / Double(count)
        let y: Double = Double(pad.minY) + height * v
        let x: Double = dustFront(v, f, sweep)
        hull.addLine(to: CGPoint(x: x, y: y))
        if i == count || x < Double(pad.minX) - 8 || x > Double(pad.maxX) + 8 { continue }
        let y2: Double = y + height / Double(count)
        let x2: Double = dustFront(Double(i + 1) / Double(count), f, sweep)
        let n: Double = closeHash(i, 6, f.seed)
        let bite: Double = 1 + 10 * n * n
        crust.move(to: CGPoint(x: x - bite, y: y))
        crust.addLine(to: CGPoint(x: x, y: y))
        crust.addLine(to: CGPoint(x: x2, y: y2))
        crust.addLine(to: CGPoint(x: x2 - bite * 0.6, y: y2))
        crust.closeSubpath()
        if n > 0.59 {
            filigree.move(to: CGPoint(x: x - 0.7, y: y))
            filigree.addLine(to: CGPoint(x: lerp(x, x2, 0.68) - 0.7, y: lerp(y, y2, 0.68)))
        }
    }
    hull.addLine(to: CGPoint(x: pad.minX - 4, y: pad.maxY + 1))
    hull.closeSubpath()
    var intact = ctx
    intact.clip(to: hull)
    f.drawPad(intact)
    var edge = ctx
    edge.clip(to: f.padPath)
    let strike: Double = smoothstep(0.02, 0.15, f.t)
    edge.fill(crust, with: .color(mist.alpha(0.25 * strike).color))
    edge.stroke(filigree, with: .color(rim.alpha(0.69 * strike).color), lineWidth: 1.15)
}

// Small radial puffs give the gust depth without a canvas-sized blur.
private func dustClouds(_ f: CloseFrame, _ ctx: GraphicsContext, _ mist: RGBA) {
    if f.t >= 0.88 { return }
    let pad = f.pad
    for i in 0..<16 {
        let n: Double = closeHash(i, 0, f.seed)
        let m: Double = closeHash(i, 5, f.seed)
        let v: Double = (Double(i) + 0.25 + 0.5 * n) / 16
        let lag: Double = 0.085 + 0.14 * n
        let x0: Double = dustFront(v, f, smoothstep(0.004, 0.74, f.t - lag))
        let fadeIn: Double = smoothstep(Double(pad.minX) - 25, Double(pad.minX) + 18, x0)
        let fadeOut: Double = 1 - smoothstep(Double(pad.maxX) - 39, Double(pad.maxX) - 2, x0)
        let pe: Double = fadeIn * fadeOut
        if pe <= 0 { continue }
        let drift: Double = 30 + 68 * n
        let cx: Double = x0 + drift
        let cy: Double = Double(pad.minY) + v * Double(pad.height) - 30 * (m - 0.28)
        let radius: Double = 26 + m * 42
        var g = ctx
        g.translateBy(x: cx, y: cy)
        g.rotate(by: .radians(-0.27 + m * 0.44))
        g.scaleBy(x: 1, y: 0.38 + 0.36 * m)
        let fog = mist.mix(f.bg, 0.29).alpha(pe * (0.10 + 0.07 * m))
        let gradient = Gradient(colors: [fog.color, fog.alpha(fog.a * 0.47).color, fog.alpha(0).color])
        let blob = Path(ellipseIn: CGRect(x: -radius, y: -radius, width: 2 * radius, height: 2 * radius))
        g.fill(blob, with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: radius))
    }
}

private func dustGrain(_ x: Double, _ y: Double, _ r: Double, _ angle: Double, _ aspect: Double) -> Path {
    let u: Double = cos(angle) * r
    let v: Double = sin(angle) * r
    let sx: Double = -v * aspect
    let sy: Double = u * aspect
    return Path { p in
        p.move(to: CGPoint(x: x - u, y: y - v))
        p.addLine(to: CGPoint(x: x + sx, y: y + sy))
        p.addLine(to: CGPoint(x: x + u, y: y + v))
        p.addLine(to: CGPoint(x: x + 0.6 * u - sx, y: y + 0.6 * v - sy))
        p.closeSubpath()
    }
}

private func dustScatter(_ f: CloseFrame, _ ctx: GraphicsContext, _ mist: RGBA, _ sweep: Double) {
    let t: Double = f.t
    let pad = f.pad
    let cells = f.cells
    let travel: Double = 1.31 * Double(pad.width) + 68
    let sample: Double = min(1, 1520 / Double(cells.rows * cells.cols))
    let settle: Double = smoothstep(0.65, 0.94, t)
    var wind = Path()
    for row in 0..<cells.rows {
        for col in 0..<cells.cols {
            if closeHash(col, row, f.seed ^ 0xCAB1) > sample { continue }
            let c = cells.color(col, row)
            if c.a < 0.09 { continue }
            let cell = cells.rect(col, row)
            let n: Double = closeHash(col, row, f.seed ^ 0x3119)
            let m: Double = closeHash(col, row, f.seed ^ 0xAB3D)
            let j: Double = closeHash(col, row, f.seed ^ 0x51ED)
            let px: Double = Double(cell.minX) + n * cells.size
            let py: Double = Double(cell.minY) + m * cells.size
            let v: Double = (py - Double(pad.minY)) / Double(pad.height)
            let startX: Double = dustFront(v, f, 0)
            let gap: Double = px - (startX - sweep * travel) + 5 * j
            if gap <= 0 { continue }
            // Invert the sweep so each flake starts exactly at the torn edge.
            let at: Double = clamp01((startX - px - 5 * j) / travel)
            let born: Double = 0.004 + 0.736 * (0.5 - sin(asin(1 - 2 * at) / 3))
            let life: Double = phase(t, born, min(0.98, born + 0.24 + 0.29 * n))
            if life <= 0 || life >= 1 { continue }
            let age: Double = pow(life, 1.18)
            let gust: Double = sin(v * 17 + age * 6 + px * 0.014)
            let drift: Double = (37 + 164 * m) * age
            let x0: Double = px + drift + 21 * gust * age
            let y0: Double = py + (-94 + 148 * j) * age
            let y1: Double = y0 + 30 * sin(v * 13 - age * 7) * age
            let gather: Double = settle * smoothstep(0.43, 0.61, born)
            let x: Double = lerp(x0, Double(f.target.x), gather)
            let y: Double = lerp(y1, Double(f.target.y) + 1, gather)
            let flake: Double = n > 0.87 ? 2.6 + 2.1 * j : 0.66 + 1.9 * m * m
            let size: Double = flake * (1 - 0.62 * age)
            let a: Double = c.a * smoothstep(0, 0.065, life) * (1 - smoothstep(0.42, 1, life))
            let ash = c.mix(mist, (0.32 + 0.44 * m) * (0.88 + 0.12 * life))
            let angle: Double = 0.3 + 5.8 * n + (5 * j - 2.5) * age
            let shape = dustGrain(x, y, size, angle, 0.28 + 0.63 * j)
            ctx.fill(shape, with: .color(ash.alpha(a).color))
            if j > 0.69 && life > 0.12 && life < 0.8 {
                let wx: Double = x - 3.5 - 12 * m
                let wy: Double = y + 4 * gust
                wind.move(to: CGPoint(x: wx, y: wy))
                wind.addQuadCurve(to: CGPoint(x: x - 0.8, y: y),
                                  control: CGPoint(x: lerp(wx, x, 0.54), y: wy + 1.8))
            }
        }
    }
    let flow: Double = 0.14 * (1 - smoothstep(0.76, 0.96, t))
    ctx.stroke(wind, with: .color(mist.alpha(flow).color), lineWidth: 0.65)
}
