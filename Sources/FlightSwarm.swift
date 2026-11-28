import SwiftUI

struct SwarmFlight: FlightEffectRenderer {
    let duration: Double = 1.31

    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) {
        let t: Double = f.t
        if t <= 0 { f.drawFrom(ctx); return }
        if t >= 1 { f.drawTo(ctx); return }

        let route = SwarmRoute(f)
        let cols = max(8, min(14, Int((Double(f.from.width) / 38).rounded())))
        let rows = max(5, min(9, Int((Double(f.from.height) / 37).rounded())))
        let fromShape = f.fromPath
        let toShape = f.toPath
        let pewter = f.dark ? RGBA(0.54, 0.65, 0.75) : RGBA(0.22, 0.27, 0.36)
        let edge = f.accent.mix(pewter, 0.48)
        let spec = edge.mix(.white, 0.55)
        var keep = Path()
        var landed = Path()
        var glints = Path()
        var trails = Path()

        for row in 0..<rows {
            for col in 0..<cols {
                let u: Double = (Double(col) + 0.5) / Double(cols)
                let v: Double = (Double(row) + 0.5) / Double(rows)
                let n: Double = closeHash(col, row, f.seed ^ 0xC729)
                let m: Double = closeHash(col, row, f.seed ^ 0x26A6)
                let projection: Double = route.ux * (u - 0.5) + route.uy * (v - 0.5)
                let front: Double = clamp01(0.5 + 0.85 * projection)
                let launch: Double = 0.020 + 0.197 * (1 - front) + 0.042 * n
                let landing: Double = 0.735 + 0.172 * (1 - front) + 0.026 * m
                if t <= launch {
                    keep.addPath(swarmTile(f.from, col, row, cols, rows, f.seed))
                    continue
                }
                if t >= landing {
                    landed.addPath(swarmTile(f.to, col, row, cols, rows, f.seed))
                    if t - landing < 0.07 && n > 0.47 {
                        let x: Double = Double(f.to.minX) + Double(f.to.width) * Double(col) / Double(cols)
                        let y: Double = Double(f.to.minY) + Double(f.to.height) * v
                        let shine: Double = sin(Double.pi * phase(t, landing, landing + 0.07))
                        glints.move(to: CGPoint(x: x, y: y + 8 * shine))
                        glints.addLine(to: CGPoint(x: x + 2, y: y - 7 * shine))
                    }
                    continue
                }

                let q: Double = phase(t, launch, landing)
                let chip = SwarmChip(f, route, q, u, v, n, m)
                if q < 0.23 || q > 0.78 {
                    // Preserve the note's own pixels as each tile lifts or fits.
                    let out = q < 0.23
                    let rect = out ? f.from : f.to
                    let tile = swarmTile(rect, col, row, cols, rows, f.seed)
                    swarmImage(f, ctx, chip, rect, tile, out ? fromShape : toShape, out)
                }
                swarmBird(f, ctx, chip, edge, spec, &trails)
            }
        }

        if !keep.isEmpty {
            var g = ctx
            g.clip(to: fromShape)
            g.clip(to: keep)
            f.drawFrom(g)
        }
        if !landed.isEmpty {
            var g = ctx
            g.clip(to: toShape)
            g.clip(to: landed)
            f.drawTo(g)
        }
        ctx.stroke(trails, with: .color(edge.alpha(0.30).color), lineWidth: 0.9)
        if !glints.isEmpty {
            var g = ctx
            g.clip(to: toShape)
            let settle: Double = 0.24 * (1 - smoothstep(0.92, 0.99, t))
            g.stroke(glints, with: .color(spec.alpha(settle).color), lineWidth: 1)
        }
    }
}

private struct SwarmRoute {
    let dx: Double, dy: Double, ux: Double, uy: Double, hx: Double, hy: Double, bow: Double

    init(_ f: FlightFrame) {
        dx = Double(f.to.midX) - Double(f.from.midX)
        dy = Double(f.to.midY) - Double(f.from.midY)
        let d: Double = max(1, f.distance)
        ux = dx / d
        uy = dy / d
        hx = -uy
        hy = ux
        let x: Double = max(Double(f.from.midX), Double(f.to.midX))
        let room: Double = max(5, min(115, Double(f.size.width) - x - 42))
        bow = min(room, 34 + d * 0.17)
    }
}

private struct SwarmChip {
    let x: Double, y: Double, q: Double, p: Double, u: Double, v: Double
    let n: Double, m: Double, bank: Double, angle: Double

    init(_ f: FlightFrame, _ r: SwarmRoute, _ q: Double, _ u: Double, _ v: Double, _ n: Double, _ m: Double) {
        self.q = q
        self.u = u
        self.v = v
        self.n = n
        self.m = m
        p = smoothstep(0, 1, q)
        let gather: Double = smoothstep(0.02, 0.28, q) * (1 - smoothstep(0.69, 1, q))
        let roll: Double = sin(p * Double.pi * 2.4 - 0.9)
        bank = sin(p * 12 - v * 5 + u * 2)
        let lift: Double = sin(Double.pi * p)
        let cx: Double = lerp(Double(f.from.midX), Double(f.to.midX), p) + r.hx * r.bow * lift
        let cy: Double = lerp(Double(f.from.midY), Double(f.to.midY), p) + r.hy * r.bow * lift
        let ax: Double = lerp(Double(f.from.width), Double(f.to.width), p) * (u - 0.5)
        let ay: Double = lerp(Double(f.from.height), Double(f.to.height), p) * (v - 0.5)
        let projection: Double = ax * r.ux + ay * r.uy
        let along: Double = projection * 0.6 + (m - 0.5) * 60 + 21 * bank
        let spread: Double = 1 + 0.35 * roll
        let cross: Double = ax * r.hx + ay * r.hy
        let across: Double = spread * (cross * 0.37 + (n - 0.5) * 47)
        let lobe: Double = n > 0.5 ? 1 : -1
        let fork: Double = lobe * (23 + 14 * roll) * sin(2.4 * p + 0.4)
        x = cx + lerp(ax, r.ux * along + r.hx * (across + fork), gather)
        y = cy + lerp(ay, r.uy * along + r.hy * (across + fork), gather)
        let bend: Double = r.bow * Double.pi * cos(Double.pi * p)
        let heading: Double = atan2(r.dy + r.hy * bend, r.dx + r.hx * bend)
        angle = heading + 0.54 * bank + 0.48 * roll + 0.30 * (n - 0.5)
    }
}

// Adjacent tiles share their jittered corners and register at both ends.
private func swarmTile(_ r: CGRect, _ col: Int, _ row: Int, _ cols: Int, _ rows: Int, _ seed: UInt32) -> Path {
    func point(_ i: Int, _ j: Int) -> CGPoint {
        let h: Double = closeHash(i, j, seed)
        let k: Double = closeHash(i, j, seed ^ 0xF103)
        let dx: Double = i == 0 || i == cols ? 0 : 0.60 * (h - 0.5)
        let dy: Double = j == 0 || j == rows ? 0 : 0.44 * (k - 0.5)
        let x: Double = Double(r.minX) + Double(r.width) * (Double(i) + dx) / Double(cols)
        let y: Double = Double(r.minY) + Double(r.height) * (Double(j) + dy) / Double(rows)
        return CGPoint(x: x, y: y)
    }
    return Path { p in
        p.move(to: point(col, row))
        p.addLine(to: point(col + 1, row))
        p.addLine(to: point(col + 1, row + 1))
        p.addLine(to: point(col, row + 1))
        p.closeSubpath()
    }
}

private func swarmImage(_ f: FlightFrame, _ ctx: GraphicsContext, _ c: SwarmChip, _ rect: CGRect,
                        _ tile: Path, _ silhouette: Path, _ out: Bool) {
    let fold: Double = out ? smoothstep(0, 0.23, c.q) : 1 - smoothstep(0.78, 1, c.q)
    let x: Double = Double(rect.minX) + Double(rect.width) * c.u
    let y: Double = Double(rect.minY) + Double(rect.height) * c.v
    var g = ctx
    g.translateBy(x: c.x, y: c.y)
    g.rotate(by: .radians((c.n - 0.5) * 2.1 * fold))
    g.scaleBy(x: 1 - 0.61 * fold, y: 1 - 0.80 * fold)
    g.translateBy(x: -x, y: -y)
    g.clip(to: tile)
    g.clip(to: silhouette)
    let alpha: Double = 1 - smoothstep(0.56, 1, fold)
    if out { f.drawFrom(g, opacity: alpha) }
    else { f.drawTo(g, opacity: alpha) }
}

private func swarmBird(_ f: FlightFrame, _ ctx: GraphicsContext, _ c: SwarmChip,
                       _ edge: RGBA, _ spec: RGBA, _ trails: inout Path) {
    let on: Double = smoothstep(0.10, 0.26, c.q) * (1 - smoothstep(0.77, 0.91, c.q))
    if on <= 0 { return }
    let from = f.fromCells.color(Int(c.u * Double(f.fromCells.cols)), Int(c.v * Double(f.fromCells.rows)))
    let to = f.toCells.color(Int(c.u * Double(f.toCells.cols)), Int(c.v * Double(f.toCells.rows)))
    let metal = from.mix(to, c.p).mix(edge, 0.33 + 0.38 * c.m)
    let span: Double = 5.1 + 8.5 * c.m * c.m
    let wing: Double = 0.87 + 4.8 * (0.50 + 0.50 * cos(c.p * 19 - c.v * 6 + c.n))
    let ux: Double = cos(c.angle)
    let uy: Double = sin(c.angle)
    func pt(_ a: Double, _ b: Double) -> CGPoint {
        CGPoint(x: c.x + ux * a - uy * b, y: c.y + uy * a + ux * b)
    }
    let nose = pt(span, 0)
    let flank = pt(-0.60 * span, wing)
    let valley = pt(-0.25 * span, 0)
    let tip = pt(-0.94 * span, -0.72 * wing)
    let body = Path { p in
        p.move(to: nose)
        p.addLine(to: flank)
        p.addLine(to: valley)
        p.addLine(to: tip)
        p.closeSubpath()
    }
    let fold = Path { p in
        p.move(to: nose)
        p.addLine(to: flank)
        p.addLine(to: valley)
        p.closeSubpath()
    }
    let shade = metal.mix(.black, f.dark ? 0.15 : 0.23).alpha(0.93 * on)
    let gleam = metal.mix(spec, 0.36 + 0.51 * (0.5 + 0.5 * c.bank)).alpha(0.96 * on)
    ctx.fill(body, with: .color(shade.color))
    ctx.fill(fold, with: .color(gleam.color))
    if c.n > 0.71 && on > 0.5 {
        trails.move(to: pt(-(span + 8 + 16 * c.m), 0))
        trails.addLine(to: valley)
    }
}
