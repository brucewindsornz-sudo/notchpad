import SwiftUI

private let beamNavy = RGBA(0.055, 0.16, 0.39)
private let beamBlue = RGBA(0.15, 0.55, 0.99)
private let beamIce = RGBA(0.61, 0.96, 1)
private let beamSilver = RGBA(1, 0.98, 0.87)

private func beamLine(_ path: inout Path, _ x: Double, _ y: Double, _ ex: Double, _ ey: Double) {
    path.move(to: CGPoint(x: x, y: y))
    path.addLine(to: CGPoint(x: ex, y: ey))
}

private func beamHalo(_ ctx: GraphicsContext, _ p: CGPoint, _ r: Double, _ c: RGBA) {
    let paint = Gradient(stops: [
        .init(color: c.color, location: 0),
        .init(color: c.alpha(c.a * 0.32).color, location: 0.42),
        .init(color: c.alpha(0).color, location: 1)
    ])
    let rect = CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2)
    ctx.fill(Path(ellipseIn: rect), with: .radialGradient(paint, center: p, startRadius: 0, endRadius: r))
}

struct BeamFlight: FlightEffectRenderer {
    let duration: Double = 1.22

    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) {
        if f.t <= 0 { f.drawFrom(ctx); return }
        if f.t >= 1 { f.drawTo(ctx); return }
        let tint = beamBlue.mix(f.accent, 0.18)
        let source = CGPoint(x: f.from.midX, y: f.from.midY)
        let destination = CGPoint(x: f.notch.midX, y: f.notch.maxY - 2)
        if f.t < 0.51 { beamTerminal(f, ctx, false, phase(f.t, 0, 0.51), source, tint) }
        if f.t > 0.49 { beamTerminal(f, ctx, true, 1 - phase(f.t, 0.49, 0.994), destination, tint) }
        beamTransmission(f, ctx, source, destination, tint)
    }

    private func beamTerminal(_ f: FlightFrame, _ ctx: GraphicsContext, _ landing: Bool, _ q: Double,
                              _ origin: CGPoint, _ tint: RGBA) {
        let r = landing ? f.to : f.from
        let shape = landing ? f.toPath : f.fromPath
        let seed = f.seed &+ (landing ? 2207 : 0)
        let n = 30
        let x0 = Double(r.minX), y0 = Double(r.minY), mx = Double(r.midX)
        let width = Double(r.width), height = Double(r.height)
        let h = height / Double(n), w = width / Double(n)
        var intact = Path(), ghost = Path()
        var lanes: [CGRect] = []
        func drawCard(_ g: GraphicsContext, _ opacity: Double = 1) {
            if landing { f.drawTo(g, opacity: opacity) }
            else { f.drawFrom(g, opacity: opacity) }
        }

        // Departure folds left and right into an optical column. Arrival scans down from the notch.
        for i in 0..<n {
            let index = Double(i)
            let y = y0 + h * index
            let theta = (index / Double(n) - 0.57) * Double.pi * 2
            let bow = 0.5 + 0.5 * cos(theta)
            let n0 = 0.77 * bow + 0.23 * closeHash(i, 15, seed)
            let gone = easeInOut(phase(q, 0.014 + n0 * 0.097, 0.60 + n0 * 0.12))
            if !landing {
                let half = width * 0.5 * (1 - gone)
                if half > 0.01 { intact.addRect(CGRect(x: mx - half, y: y, width: half * 2, height: h)) }
                let edge = min(width * 0.5 - half, 7 + n0 * 24)
                if edge > 0.06 {
                    let left = CGRect(x: mx - half - edge, y: y, width: edge, height: h)
                    let right = CGRect(x: mx + half, y: y, width: edge, height: h)
                    ghost.addRect(left)
                    ghost.addRect(right)
                    lanes.append(left)
                    lanes.append(right)
                }
            } else {
                let x = x0 + index * w
                let remain = height * (1 - gone)
                if remain > 0.01 { intact.addRect(CGRect(x: x, y: y0, width: w, height: remain)) }
                let edge = min(height - remain, 14 + n0 * 32)
                if edge > 0.06 {
                    let lane = CGRect(x: x, y: y0 + remain, width: w, height: edge)
                    ghost.addRect(lane)
                    lanes.append(lane)
                }
            }
        }
        if !intact.isEmpty {
            var g = ctx
            g.clip(to: intact)
            drawCard(g)
        }
        let glow = smoothstep(0.01, 0.21, q) * (1 - smoothstep(0.55, 0.89, q))
        if !ghost.isEmpty && glow > 0 {
            var g = ctx
            g.clip(to: shape)
            g.clip(to: ghost)
            drawCard(g, 0.19 * glow)
            let paint = Gradient(stops: [
                .init(color: tint.alpha(0.53 * glow).color, location: 0),
                .init(color: beamIce.alpha(0.29 * glow).color, location: 0.19),
                .init(color: tint.alpha(0).color, location: 1)
            ])
            for (i, a) in lanes.enumerated() {
                let startX = landing || i % 2 != 0 ? a.minX : a.maxX
                let endX = landing || i % 2 == 0 ? a.minX : a.maxX
                let start = CGPoint(x: startX, y: a.minY)
                let end = CGPoint(x: endX, y: landing ? a.maxY : a.minY)
                g.fill(Path(a), with: .linearGradient(paint, startPoint: start, endPoint: end))
            }
        }
        let dissolve = smoothstep(0.13, 0.86, q)
        beamFibres(ctx, r, origin, tint, seed, q, dissolve, glow, landing)
        let cells = landing ? f.toCells : f.fromCells
        beamGlitter(ctx, r, origin, cells, seed, q, glow)
        let flare = smoothstep(0.60, 0.83, q) * (1 - smoothstep(0.88, 1, q))
        if flare > 0 { beamHalo(ctx, origin, 46 * flare + 12, tint.alpha(0.83 * flare)) }
    }

    private func beamFibres(_ ctx: GraphicsContext, _ r: CGRect, _ origin: CGPoint, _ tint: RGBA, _ seed: UInt32,
                            _ q: Double, _ dissolve: Double, _ glow: Double, _ landing: Bool) {
        let ox = Double(origin.x), oy = Double(origin.y)
        let w = Double(r.width), h = Double(r.height)
        let bloom = smoothstep(0.4, 0.72, q) * (1 - smoothstep(0.78, 0.96, q))
        if bloom > 0 {
            let y = landing ? oy - 21 : oy - h * 0.3
            let height = h * 0.61 * (1 - 0.6 * dissolve)
            let half = lerp(44, 7, dissolve)
            let paint = Gradient(stops: [
                .init(color: tint.alpha(0).color, location: 0), .init(color: tint.alpha(0.50 * bloom).color, location: 0.39),
                .init(color: beamIce.alpha(0.71 * bloom).color, location: 0.5),
                .init(color: tint.alpha(0.50 * bloom).color, location: 0.61), .init(color: tint.alpha(0).color, location: 1)
            ])
            let p = Path(ellipseIn: CGRect(x: ox - half, y: y, width: 2 * half, height: height))
            let start = CGPoint(x: ox - half, y: y), end = CGPoint(x: ox + half, y: y)
            ctx.fill(p, with: .linearGradient(paint, startPoint: start, endPoint: end))
        }
        guard glow > 0 else { return }
        let ax = min(71, w * 0.17)
        var fibres = Path(), cores = Path()
        let span = 0.45 + 0.55 * sin(Double.pi * q)
        for i in 0..<38 {
            let x0 = closeHash(i, 28, seed), u = closeHash(i, 29, seed), v = closeHash(i, 30, seed)
            let x = lerp(Double(r.minX) + w * x0, ox + (x0 - 0.5) * ax, dissolve)
            let y = lerp(Double(r.minY) + h * u, oy, dissolve)
            let len = (13 + v * v * (h * 0.45)) * span
            beamLine(&fibres, x, y - len * 0.50, x, y + len * 0.72)
            if i % 3 != 0 { beamLine(&cores, x + 0.6, y - len * 0.28, x + 0.6, y + len * 0.44) }
        }
        ctx.stroke(fibres, with: .color(beamNavy.alpha(glow * 0.28).color), lineWidth: 4.2)
        ctx.stroke(fibres, with: .color(tint.alpha(glow * 0.71).color), lineWidth: 2.35)
        ctx.stroke(cores, with: .color(beamIce.alpha(glow * 0.92).color), lineWidth: 0.95)
    }

    private func beamGlitter(_ ctx: GraphicsContext, _ r: CGRect, _ origin: CGPoint, _ cells: CloseCells,
                             _ seed: UInt32, _ q: Double, _ glow: Double) {
        let ox = Double(origin.x), oy = Double(origin.y)
        let x0 = Double(r.minX), y0 = Double(r.minY)
        let w = Double(r.width), h = Double(r.height)
        var spray = Path()
        for i in 0..<162 {
            let u = closeHash(i, 70, seed), v = closeHash(i, 71, seed)
            let tintCell = cells.color(Int(u * Double(cells.cols)), Int(v * Double(cells.rows)))
            if tintCell.a < 0.18 { continue }
            let k = closeHash(i, 72, seed), d = closeHash(i, 73, seed)
            let age = phase(q, 0.05 + 0.26 * k, 0.76 + d * 0.22)
            if age <= 0 || age >= 1 { continue }
            let gather = smoothstep(0.08, 0.97, age)
            let angle = (u + age * (0.54 + 0.52 * d)) * Double.pi * 2
            let swirl = sin(Double.pi * age) * (17 + 33 * k)
            let x = lerp(x0 + w * u, ox, gather) + sin(angle) * swirl
            let y = lerp(y0 + h * v, oy, gather) - swirl * 0.63
            let flicker = 0.37 + 0.63 * pow(0.5 + 0.5 * sin(angle * 4 + d * 8), 3)
            let a = smoothstep(0, 0.20, age) * (1 - smoothstep(0.68, 1, age)) * flicker
            let s = (0.63 + k * 1.28) * (1 - 0.56 * gather)
            let c = tintCell.mix(i % 8 == 0 ? beamSilver : beamIce, 0.76 + 0.22 * d)
            let grain = CGRect(x: x - s, y: y - s * 1.4, width: s * 2, height: s * 2.8)
            ctx.fill(Path(ellipseIn: grain), with: .color(c.alpha(a).color))
            if i % 6 == 0 && a > 0.48 {
                beamLine(&spray, x, y - s * 3.4, x, y + s * 3.4)
                beamLine(&spray, x - s * 1.5, y, x + s * 1.5, y)
            }
        }
        ctx.stroke(spray, with: .color(beamSilver.alpha(glow * 0.83).color), lineWidth: 0.95)
    }

    private func beamTransmission(_ f: FlightFrame, _ ctx: GraphicsContext, _ source: CGPoint,
                                  _ dest: CGPoint, _ tint: RGBA) {
        guard f.t > 0.31 && f.t < 0.68 else { return }
        let q = phase(f.t, 0.31, 0.68)
        let sx = Double(source.x), sy = Double(source.y), ex = Double(dest.x), ey = Double(dest.y)
        let dx = ex - sx, dy = ey - sy
        let fullLen = hypot(dx, dy)
        let nx = -dy / max(1, fullLen), ny = dx / max(1, fullLen)
        let spread = min(12, fullLen * 0.09)
        let head = easeInOut(phase(q, 0, 0.73)), tail = easeInOut(phase(q, 0.21, 1))
        let strength = smoothstep(0, 0.18, q) * (1 - smoothstep(0.75, 1, q))
        func centre(_ u: Double) -> CGPoint { CGPoint(x: lerp(sx, ex, u), y: lerp(sy, ey, u)) }
        var ray = Path()
        ray.move(to: centre(tail))
        ray.addLine(to: centre(head))
        // Indigo shows on bright desktops. The thin ice core carries it on dark ones.
        ctx.stroke(ray, with: .color(beamNavy.alpha(strength * 0.34).color), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        ctx.stroke(ray, with: .color(tint.alpha(strength * 0.38).color), style: StrokeStyle(lineWidth: 7.8, lineCap: .round))
        ctx.stroke(ray, with: .color(beamIce.alpha(strength * 0.87).color), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        for i in 0..<2 {
            var p = Path()
            for j in 0...28 {
                let v = Double(j) / 28, u = lerp(tail, head, v)
                let c = centre(u)
                let a = u * 25 - q * 9 + Double.pi * Double(i)
                let wave = sin(a) * sin(Double.pi * v) * spread
                let s = CGPoint(x: Double(c.x) + nx * wave, y: Double(c.y) + ny * wave)
                if j == 0 { p.move(to: s) } else { p.addLine(to: s) }
            }
            let c = i == 0 ? tint : beamIce
            ctx.stroke(p, with: .color(c.alpha(strength * 0.57).color), lineWidth: 1.17)
        }
        let tip = centre(head)
        let x = Double(tip.x), y = Double(tip.y)
        let pulse = strength * (1 - 0.38 * smoothstep(0.65, 1, q))
        beamHalo(ctx, tip, 18 + 27 * pulse, tint.alpha(pulse * 0.79))
        var star = Path(), core = Path()
        let hx = 8 + 18 * pulse
        beamLine(&star, x - hx, y, x + hx, y)
        beamLine(&star, x, y - hx * 0.74, x, y + hx * 0.74)
        let bend = 2.6 + 6.4 * pulse
        beamLine(&core, x - bend, y, x + bend, y)
        beamLine(&core, x, y - bend * 0.65, x, y + bend * 0.65)
        ctx.stroke(star, with: .color(beamNavy.alpha(pulse * 0.38).color), lineWidth: 2.8)
        ctx.stroke(star, with: .color(beamIce.alpha(pulse * 0.84).color), lineWidth: 1.15)
        ctx.stroke(core, with: .color(beamSilver.alpha(pulse).color), lineWidth: 1.8)
    }
}
