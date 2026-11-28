import SwiftUI

struct BoltFlight: FlightEffectRenderer {
    let duration: Double = 1.07

    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) {
        let t = f.t
        if t <= 0 { f.drawFrom(ctx); return }
        if t >= 1 { f.drawTo(ctx); return }
        let src = f.from
        let ink = RGBA(0.30, 0.10, 0.78).mix(f.accent, 0.20)
        let iris = RGBA(0.64, 0.53, 1).mix(f.accent, 0.15)
        let latch = CGPoint(x: f.notch.midX, y: max(3, f.notch.maxY - 1))
        let dx = Double(latch.x - src.midX), dy = Double(latch.y - src.midY)
        let distance = max(1, hypot(dx, dy))
        let nx: Double = dx / distance, ny: Double = dy / distance
        let offset = min(95, Double(src.width) * 0.18, Double(src.height) * 0.29, distance * 0.27)
        let focus = CGPoint(x: Double(src.midX) + nx * offset, y: Double(src.midY) + ny * offset)
        boltTakeoff(f, ctx, focus, ink, iris)
        let stemLength = hypot(Double(latch.x - focus.x), Double(latch.y - focus.y))
        let count = max(14, min(51, Int((stemLength / 16).rounded())))
        let bow: Double = min(70, stemLength * 0.17) * (dx < -40 ? -1 : 1)
        let trunk = boltRoute(focus, latch, count, min(115, stemLength * 0.42 + 13), 24, f.seed, bow)
        let arrival: Double = smoothstep(0.55, 0.625, t) * (1 - smoothstep(0.64, 0.748, t))
        boltTransit(f, ctx, trunk, nx, ny, stemLength, ink, iris, arrival)
        boltDock(f, ctx, latch, ink, iris, arrival)
    }
}

private func boltTakeoff(_ f: FlightFrame, _ ctx: GraphicsContext, _ focus: CGPoint, _ ink: RGBA, _ iris: RGBA) {
    let t = f.t, src = f.from
    if t >= 0.38 { return }
    let w = Double(src.width), h = Double(src.height)
    let cx = Double(src.midX), cy = Double(src.midY)
    // The departing rows are slices of the note, each folding into the same point.
    if t <= 0.045 { f.drawFrom(ctx) }
    else {
        let bands = 13
        let band: Double = h / Double(bands)
        for i in 0..<bands {
            let y: Double = Double(src.minY) + band * Double(i)
            let mid: Double = y + band * 0.5
            let skew: Double = 0.044 * closeHash(i, 37, f.seed)
            let tuck = smoothstep(0.047 + skew, 0.385 - skew, t)
            let fade = 1 - smoothstep(0.245 + skew, 0.377, t)
            let wy = lerp(1, 0.03, tuck), wx = lerp(1, 0.022, tuck)
            let xShift: Double = (Double(focus.x) - cx) * tuck
            let ripple: Double = sin(Double(i) * 1.91) * sin(Double.pi * tuck) * 11
            let targetY: Double = lerp(mid, Double(focus.y), tuck) + ripple
            var g = ctx
            g.translateBy(x: CGFloat(cx + xShift), y: CGFloat(targetY))
            g.scaleBy(x: CGFloat(wx), y: CGFloat(wy))
            g.translateBy(x: CGFloat(-cx), y: CGFloat(-mid))
            g.clip(to: Path(CGRect(x: Double(src.minX) - 1, y: y - 0.24, width: w + 2, height: band + 0.48)))
            f.drawFrom(g, opacity: fade)
        }
    }
    let charge: Double = smoothstep(0.015, 0.115, t) * (1 - smoothstep(0.31, 0.40, t))
    var forks = Path()
    let gather = smoothstep(0.07, 0.37, t)
    for i in 0..<6 {
        let angle: Double = Double(i) / 6 * Double.pi * 2 + 0.2
        let x: Double = cx + cos(angle) * w * 0.43
        let y: Double = cy + sin(angle) * h * 0.42
        let head = boltPoint(CGPoint(x: x, y: y), focus, gather * 0.87)
        let branch = boltRoute(head, focus, 9, lerp(34, 12, gather), 60 + i * 3, f.seed)
        let a: Double = 0.019 + Double(i) * 0.012
        let b: Double = 0.19 + Double(i) * 0.012
        boltTrace(&forks, branch, 0.09, easeOut(phase(t, a, b)))
    }
    boltFilament(ctx, forks, ink, charge * 0.73, 0.98)
    boltBloom(ctx, focus, lerp(36, 73, gather), iris, charge * gather * 0.88)
}

private func boltTransit(_ f: FlightFrame, _ ctx: GraphicsContext, _ trunk: [CGPoint], _ nx: Double, _ ny: Double,
                         _ stemLength: Double, _ ink: RGBA, _ iris: RGBA, _ arrival: Double) {
    let t = f.t
    let travel = smoothstep(0.24, 0.63, t)
    let retreat = easeIn(phase(t, 0.57, 0.81))
    // The notch sends up a short streamer before the main channel makes contact.
    let feeler: Double = smoothstep(0.45, 0.60, t) * (1 - smoothstep(0.61, 0.665, t))
    if feeler > 0 {
        var upstream = Path(), twig = Path()
        let q = smoothstep(0.44, 0.618, t)
        boltTrace(&upstream, trunk, 1 - 0.25 * q, 1)
        let origin = boltSample(trunk, 0.96)
        let x: Double = Double(origin.x) - nx * 22 + ny * 26
        let y: Double = max(3, Double(origin.y) - ny * 22 - nx * 26)
        let end = CGPoint(x: x, y: y)
        boltTrace(&twig, boltRoute(origin, end, 5, 9, 151, f.seed), 0, q)
        boltFilament(ctx, upstream, iris, feeler * 0.66, 1.25)
        boltFilament(ctx, twig, ink, feeler * 0.55, 0.78)
    }
    if travel <= 0 || retreat >= 1 { return }
    var path = Path(), head = Path(), branches = Path()
    boltTrace(&path, trunk, retreat, travel)
    boltTrace(&head, trunk, max(retreat, travel - 0.26), travel)
    let count = trunk.count - 1
    for j in 0..<8 {
        let u: Double = 0.13 + Double(j) * 0.095
        let k = Int((u * Double(count)).rounded())
        if retreat >= u || travel <= u || k >= count { continue }
        let origin = trunk[k]
        let side: Double = j % 2 == 0 ? 1 : -1
        let reach: Double = min(96, stemLength * 0.42 + 15) * (0.52 + 0.47 * closeHash(j, 71, f.seed))
        let drift: Double = min(102, stemLength * 0.20) * (0.68 + 0.4 * closeHash(j, 7, f.seed))
        let x: Double = Double(origin.x) + nx * drift - ny * reach * side
        let y: Double = max(3, Double(origin.y) + ny * drift + nx * reach * side)
        let branch = boltRoute(origin, CGPoint(x: x, y: y), 8, 22, 72 + j, f.seed)
        let growing = smoothstep(u, u + 0.17, travel)
        boltTrace(&branches, branch, 0, growing)
        if j % 3 == 1 {
            let split = branch[4]
            let bend: Double = reach * side * 0.26
            let slide: Double = drift * 0.46
            let a: Double = Double(split.x) + nx * slide + ny * bend
            let b: Double = max(3, Double(split.y) + ny * slide - nx * bend)
            let end = CGPoint(x: a, y: b)
            boltTrace(&branches, boltRoute(split, end, 5, 11, 105 + j, f.seed), 0,
                      smoothstep(0.42, 0.95, growing))
        }
    }
    let live: Double = (1 - smoothstep(0.67, 0.81, t)) * smoothstep(0.245, 0.32, t)
    boltFilament(ctx, branches, ink, live * (0.57 + 0.26 * arrival), 1.02)
    boltFilament(ctx, path, ink, live * (0.52 + 0.46 * arrival), 1.55 + arrival * 1.42)
    boltFilament(ctx, head, iris, live * 0.92, 2.15)
    boltBloom(ctx, boltSample(trunk, travel), 34, iris, live * (0.61 + 0.30 * arrival))
}

private func boltDock(_ f: FlightFrame, _ ctx: GraphicsContext, _ latch: CGPoint,
                      _ ink: RGBA, _ iris: RGBA, _ arrival: Double) {
    let t = f.t, dst = f.to
    let w = Double(dst.width), h = Double(dst.height)
    let reveal = smoothstep(0.555, 0.848, t)
    if reveal >= 1 { f.drawTo(ctx) }
    if reveal > 0 && reveal < 1 {
        var mask = Path(), seam = Path()
        mask.move(to: CGPoint(x: dst.minX - 1, y: dst.minY - 2))
        mask.addLine(to: CGPoint(x: dst.maxX + 1, y: dst.minY - 2))
        for i in stride(from: 26, through: 0, by: -1) {
            let u: Double = Double(i) / 26
            let uneven: Double = (closeHash(i, 116, f.seed) - 0.5) * 14
            let offset: Double = u - 0.5
            let arch: Double = 45 * (1 - 4 * offset * offset)
            let front: Double = reveal * (h + 3)
            let wave: Double = (arch + uneven) * sin(Double.pi * reveal)
            let y: Double = Double(dst.minY) + front + wave
            let x: Double = lerp(Double(dst.minX) - 1, Double(dst.maxX) + 1, u)
            let p = CGPoint(x: x, y: y)
            mask.addLine(to: p)
            if i == 26 { seam.move(to: p) } else { seam.addLine(to: p) }
        }
        mask.closeSubpath()
        var g = ctx
        g.clip(to: f.toPath)
        var snapshot = g
        snapshot.clip(to: mask)
        f.drawTo(snapshot)
        let seamPower: Double = smoothstep(0, 0.11, reveal) * (1 - smoothstep(0.68, 0.99, reveal))
        boltFilament(g, seam, ink, seamPower * 0.75, 1.36)
    }
    if arrival > 0 {
        var g = ctx
        g.clip(to: f.toPath)
        boltBloom(g, latch, min(235, w * 0.49), iris, arrival * 0.68)
    }
    boltBloom(ctx, latch, 65, iris, arrival * 0.86)
    let tail: Double = smoothstep(0.62, 0.69, t) * (1 - smoothstep(0.743, 0.956, t))
    if tail <= 0 { return }
    var residual = Path()
    for i in 0..<5 {
        let sign: Double = i % 2 == 0 ? -1 : 1
        let a: Double = 0.62 + Double(i) * 0.010
        let b: Double = 0.85 + Double(i) * 0.015
        let u = easeOut(phase(t, a, b))
        let dx: Double = sign * w * (0.05 + 0.037 * Double(i)) * u
        let dy: Double = h * (0.08 + 0.045 * Double(i)) * u
        let end = CGPoint(x: Double(latch.x) + dx, y: Double(latch.y) + dy)
        boltTrace(&residual, boltRoute(latch, end, 8, 19 * u, 120 + i, f.seed),
                  smoothstep(0.76, 0.95, t) * 0.82, u)
    }
    boltFilament(ctx, residual, ink, tail * 0.72, 0.98)
    boltSparks(f, ctx, latch, iris)
}

private func boltSparks(_ f: FlightFrame, _ ctx: GraphicsContext, _ latch: CGPoint, _ iris: RGBA) {
    var rng = CloseRNG(f.seed ^ 0x44B1)
    for i in 0..<37 {
        let angle = rng.range(-0.12, Double.pi + 0.12), speed = rng.range(30, 144)
        let start = rng.range(0.59, 0.69), length = rng.range(2.1, 9)
        let span = rng.range(0.12, 0.28)
        let life = phase(f.t, start, start + span)
        if life <= 0 || life >= 1 { continue }
        let push: Double = speed * easeOut(life)
        let vx = cos(angle), vy = sin(angle)
        let x: Double = Double(latch.x) + vx * push
        let y: Double = Double(latch.y) + vy * push + 15 * life * life
        let l: Double = length * (1 - 0.73 * life)
        var line = Path()
        line.move(to: CGPoint(x: x - vx * l, y: y - vy * l))
        line.addLine(to: CGPoint(x: x, y: y))
        let colour = i % 4 == 0 ? RGBA.white : iris
        let opacity: Double = 0.75 * (1 - life) * smoothstep(0, 0.16, life)
        ctx.stroke(line, with: .color(colour.alpha(opacity).color), lineWidth: i % 4 == 0 ? 1.4 : 0.94)
    }
}

private func boltPoint(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
    CGPoint(x: lerp(Double(a.x), Double(b.x), u), y: lerp(Double(a.y), Double(b.y), u))
}

private func boltRoute(_ a: CGPoint, _ b: CGPoint, _ count: Int, _ amplitude: Double, _ salt: Int,
                       _ seed: UInt32, _ bow: Double = 0) -> [CGPoint] {
    let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
    let length = max(1, hypot(dx, dy))
    var points = [a]
    for i in 1..<count {
        let u: Double = Double(i) / Double(count)
        let coarse: Double = closeNoise(u * 7.1, Double(salt), seed) - 0.5
        let rough: Double = closeHash(i, salt + 13, seed) - 0.5
        let edge = sin(Double.pi * u)
        let cross: Double = (bow + amplitude * (coarse * 1.45 + rough * 0.7)) * edge
        let p = boltPoint(a, b, u)
        let x: Double = Double(p.x) - dy * cross / length
        let y: Double = Double(p.y) + dx * cross / length
        points.append(CGPoint(x: x, y: y))
    }
    points.append(b)
    return points
}

private func boltTrace(_ path: inout Path, _ points: [CGPoint], _ first: Double, _ last: Double) {
    if last <= first { return }
    let n = points.count - 1
    let a: Double = first * Double(n), b: Double = last * Double(n)
    let i = Int(a), j = Int(b)
    path.move(to: boltPoint(points[i], points[i + 1], a - Double(i)))
    if j > i {
        for k in (i + 1)...j { path.addLine(to: points[k]) }
    }
    if j < n { path.addLine(to: boltPoint(points[j], points[j + 1], b - Double(j))) }
}

private func boltSample(_ points: [CGPoint], _ u: Double) -> CGPoint {
    let x: Double = clamp01(u) * Double(points.count - 1)
    let i = min(points.count - 2, Int(x))
    return boltPoint(points[i], points[i + 1], x - Double(i))
}

private func boltFilament(_ ctx: GraphicsContext, _ path: Path, _ ink: RGBA, _ intensity: Double, _ width: Double) {
    if intensity <= 0 || path.isEmpty { return }
    func line(_ w: Double) -> StrokeStyle { StrokeStyle(lineWidth: CGFloat(w), lineCap: .round, lineJoin: .round) }
    ctx.stroke(path, with: .color(ink.alpha(0.13 * intensity).color), style: line(width * 7))
    ctx.stroke(path, with: .color(ink.alpha(0.76 * intensity).color), style: line(width * 2.5))
    var core = ctx
    core.blendMode = .plusLighter
    core.stroke(path, with: .color(ink.mix(.white, 0.91).alpha(intensity).color), style: line(width))
}

private func boltBloom(_ ctx: GraphicsContext, _ p: CGPoint, _ r: Double, _ ink: RGBA, _ intensity: Double) {
    if intensity <= 0 { return }
    let colours = Gradient(stops: [
        .init(color: RGBA.white.alpha(intensity * 0.9).color, location: 0),
        .init(color: ink.mix(.white, 0.46).alpha(intensity * 0.63).color, location: 0.14),
        .init(color: ink.alpha(intensity * 0.22).color, location: 0.42),
        .init(color: ink.alpha(0).color, location: 1)
    ])
    let box = CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2)
    ctx.fill(Path(ellipseIn: box), with: .radialGradient(colours, center: p, startRadius: 0, endRadius: CGFloat(r)))
}
