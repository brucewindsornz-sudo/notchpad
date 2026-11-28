import SwiftUI

struct LightningClose: CloseEffectRenderer {
    let duration: Double = 0.98

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let t = f.t
        if t <= 0 { f.drawPad(ctx); return }
        if t >= 1 { return }
        let r = f.pad
        let w = Double(r.width), h = Double(r.height)
        let ink = RGBA(0.16, 0.29, 0.91).mix(f.accent, 0.16)
        let hot = RGBA(0.49, 0.73, 1).mix(f.accent, 0.12)
        let impact = CGPoint(x: Double(r.minX) + w * 0.44, y: Double(r.minY) + h * 0.56)
        let entry = f.floating
            ? CGPoint(x: Double(r.midX) + w * 0.19, y: Double(r.minY) - min(71, h * 0.3))
            : CGPoint(x: f.target.x, y: max(2, f.sink.maxY - 2))
        let main = lightningChannel(entry, impact, 17, min(88, w * 0.23), 19, f.seed)
        let radius: Double = 2.02 * smoothstep(0.28, 0.76, t)
        let rx: Double = w * 0.49, ry: Double = h * 0.50
        var ring = Path()
        var teeth: [CGPoint] = []
        if radius > 0 {
            for i in 0..<64 {
                let a: Double = Double(i) / 64 * Double.pi * 2
                let rough: Double = 0.14 * closeHash(i, 94, f.seed)
                let tooth: Double = 0.92 + rough + 0.09 * sin(5 * a + 0.6)
                let px: Double = cos(a) * rx * radius * tooth
                let py: Double = sin(a) * ry * radius * tooth
                let p = CGPoint(x: Double(impact.x) + px, y: Double(impact.y) + py)
                teeth.append(p)
                if i == 0 { ring.move(to: p) } else { ring.addLine(to: p) }
            }
            ring.closeSubpath()
        }
        // Punch a hole through the actual photograph, not a translucent overlay.
        if t < 0.77 {
            var image = ctx
            if radius > 0 { image.clip(to: ring, options: .inverse) }
            f.drawPad(image)
        }
        let flash: Double = smoothstep(0.125, 0.169, t) * (1 - smoothstep(0.173, 0.278, t))
        let echo: Double = 0.25 * smoothstep(0.242, 0.275, t) * (1 - smoothstep(0.281, 0.385, t))
        let outline = f.padPath
        var inside = ctx
        inside.clip(to: outline)
        lightningHalo(inside, impact, min(240, w * 0.53), hot, 0.75 * flash + echo)
        if flash > 0 {
            var g = inside
            g.blendMode = .plusLighter
            g.fill(outline, with: .color(hot.alpha(flash * (f.dark ? 0.25 : 0.12)).color))
        }
        let sideGlow: Double = smoothstep(0.14, 0.205, t) * (1 - smoothstep(0.37, 0.65, t))
        if sideGlow > 0 {
            if radius > 0 { inside.clip(to: ring, options: .inverse) }
            lightningSidewalls(f, inside, impact, ink, sideGlow)
        }
        if t > 0.28 && t < 0.77 {
            var edge = ctx
            edge.clip(to: outline)
            let strength: Double = smoothstep(0.28, 0.35, t) * (1 - smoothstep(0.60, 0.77, t))
            var broken = Path(), streamers = Path()
            for i in teeth.indices {
                let charge = closeNoise(Double(i) * 0.12, t * 5, f.seed ^ 0xD151)
                if charge < 0.37 { continue }
                broken.move(to: teeth[i])
                broken.addLine(to: teeth[(i + 1) % teeth.count])
                if i % 6 == 1 && i < teeth.count - 1 {
                    let twig = lightningPoint(teeth[i], impact, 0.045 + 0.12 * charge)
                    streamers.move(to: teeth[i + 1])
                    streamers.addLine(to: lightningPoint(teeth[i], twig, 0.59))
                    streamers.addLine(to: twig)
                }
            }
            edge.stroke(ring, with: .color(ink.alpha(strength * 0.31).color), lineWidth: 4)
            lightningTube(edge, broken, hot, strength * 0.88, 1.05)
            lightningTube(edge, streamers, ink, strength * 0.60, 0.81)
        }
        lightningStrike(f, ctx, main, ink, flash, echo)
        lightningEmbers(f, ctx, impact, rx, ry, ink, hot)
        let after: Double = smoothstep(0.42, 0.55, t) * (1 - smoothstep(0.64, 0.88, t))
        if after > 0 { ctx.stroke(outline, with: .color(ink.alpha(after * 0.22).color), lineWidth: 1) }
        let sink = f.floating ? f.target : entry
        if f.floating {
            let closing = easeInOut(phase(t, 0.62, 0.89))
            let tail = lightningChannel(impact, sink, 7, 13, 94, f.seed)
            var residual = Path()
            lightningTrace(&residual, tail, 0.72 * closing, easeOut(phase(t, 0.52, 0.73)))
            let tailPower: Double = smoothstep(0.52, 0.64, t) * (1 - smoothstep(0.82, 0.94, t))
            lightningTube(ctx, residual, ink, 0.42 * tailPower, 1.2)
        }
        let last: Double = smoothstep(0.71, 0.825, t) * (1 - smoothstep(0.84, 0.975, t))
        if last > 0 {
            lightningHalo(ctx, sink, 25, ink, last * 0.56)
            var pin = Path()
            pin.move(to: CGPoint(x: Double(sink.x) - 8 * last, y: Double(sink.y)))
            pin.addLine(to: CGPoint(x: Double(sink.x) + 8 * last, y: Double(sink.y)))
            lightningTube(ctx, pin, ink, last * 0.72, 1.2)
        }
    }
}

private func lightningSidewalls(_ f: CloseFrame, _ ctx: GraphicsContext, _ impact: CGPoint,
                                _ ink: RGBA, _ power: Double) {
    let r = f.pad, t = f.t
    let w = Double(r.width), h = Double(r.height)
    let spread = easeOut(phase(t, 0.155, 0.43))
    let inset: Double = f.floating ? 7 : 15
    var forks = Path(), walls = Path()
    for side in [-1, 1] {
        let junction = lightningRimPoint(r, side, side < 0 ? 0.37 : 0.68, inset)
        let arm = lightningChannel(impact, junction, 17, h * 0.32, side + 72, f.seed)
        lightningTrace(&forks, arm, 0, spread)
        for end in [0, 1] {
            let tip = lightningRimPoint(r, side, Double(end), inset)
            let rim = lightningChannel(junction, tip, 10, 15, side + end * 5 + 92, f.seed)
            lightningTrace(&walls, rim, 0, easeOut(phase(t, 0.25, 0.52)))
        }
        for j in 0..<3 {
            let k = 3 + j * 4
            let root = arm[k]
            let dx: Double = Double(side) * w * (0.07 + 0.028 * Double(j))
            let dy: Double = h * (j % 2 == 0 ? -0.19 : 0.16)
            let dest = CGPoint(x: Double(root.x) + dx, y: Double(root.y) + dy)
            let branch = lightningChannel(root, dest, 7, 18, 38 + j * 5 + side, f.seed)
            let a: Double = 0.235 + Double(k) * 0.008
            let b: Double = 0.44 + Double(k) * 0.007
            lightningTrace(&forks, branch, 0, easeOut(phase(t, a, b)))
        }
    }
    lightningTube(ctx, walls, ink, power * 0.88, 1.45)
    lightningTube(ctx, forks, ink, power * 0.79, 1.1)
}

private func lightningStrike(_ f: CloseFrame, _ ctx: GraphicsContext, _ main: [CGPoint],
                             _ ink: RGBA, _ flash: Double, _ echo: Double) {
    let t = f.t, r = f.pad
    let leader = easeOut(phase(t, 0.036, 0.163))
    let retreat = easeIn(phase(t, 0.40, 0.88))
    var trunk = Path(), twigs = Path()
    lightningTrace(&trunk, main, 0, leader * (1 - retreat))
    if t < 0.47 {
        let w = Double(r.width), h = Double(r.height)
        for j in 0..<5 {
            let origin = main[3 + j * 2]
            let side: Double = j % 2 == 0 ? -1 : 1
            let dx: Double = w * (0.08 + Double(j) * 0.012) * side
            let dy: Double = min(h * 0.22, 63) * (0.68 + 0.12 * Double(j))
            let dest = CGPoint(x: Double(origin.x) + dx, y: Double(origin.y) + dy)
            let branch = lightningChannel(origin, dest, 8, 19, 56 + j, f.seed)
            let a: Double = 0.057 + Double(j) * 0.013
            let b: Double = 0.16 + Double(j) * 0.014
            lightningTrace(&twigs, branch, 0, easeOut(phase(t, a, b)))
        }
    }
    let energy: Double = smoothstep(0.039, 0.136, t) * (1 - smoothstep(0.29, 0.87, t))
    let current: Double = 0.27 + 0.17 * closeNoise(t * 24, 13, f.seed)
    let branchPower: Double = min(1, flash * 0.69 + echo + energy * 0.36)
    lightningTube(ctx, twigs, ink, branchPower * (1 - smoothstep(0.26, 0.46, t)), 0.96)
    lightningTube(ctx, trunk, ink, min(1, flash + echo + energy * current), 1.65 + flash * 1.46)
}

private func lightningEmbers(_ f: CloseFrame, _ ctx: GraphicsContext, _ impact: CGPoint,
                             _ rx: Double, _ ry: Double, _ ink: RGBA, _ hot: RGBA) {
    if f.t <= 0.29 || f.t >= 0.963 { return }
    var rng = CloseRNG(f.seed ^ 0xAE71)
    for i in 0..<108 {
        let col = rng.int(f.cells.cols), row = rng.int(f.cells.rows)
        let angle = rng.range(-Double.pi, Double.pi), speed = rng.range(21, 115)
        let length = rng.range(1.9, 11), span = rng.range(0.18, 0.34)
        let cell = f.cells.rect(col, row)
        let nx: Double = Double(cell.midX - impact.x) / rx
        let ny: Double = Double(cell.midY - impact.y) / ry
        let radial = hypot(nx, ny)
        let start: Double = lerp(0.29, 0.70, pow(clamp01(radial / 1.57), 0.75))
        let life = phase(f.t, start, min(0.963, start + span))
        if life <= 0 || life >= 1 { continue }
        let c = f.cells.color(col, row)
        if c.a < 0.23 { continue }
        let push: Double = easeOut(life) * speed
        let vx = cos(angle), vy = sin(angle)
        let x: Double = Double(cell.midX) + vx * push
        let y: Double = Double(cell.midY) + vy * push + 28 * life * life
        let l: Double = length * (1 - 0.77 * life)
        var p = Path()
        p.move(to: CGPoint(x: x - vx * l, y: y - vy * l))
        p.addLine(to: CGPoint(x: x, y: y))
        let opacity: Double = (1 - life) * smoothstep(0, 0.14, life)
        let warm = i % 6 == 0
        let spark = c.mix(warm ? RGBA(0.99, 0.59, 0.36) : hot, 0.86)
        ctx.stroke(p, with: .color(ink.alpha(0.33 * opacity).color), lineWidth: warm ? 3 : 2.05)
        ctx.stroke(p, with: .color(spark.alpha(0.91 * opacity).color), lineWidth: warm ? 1.7 : 1.15)
        if i % 3 == 0 {
            let dot = Path(ellipseIn: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4))
            ctx.fill(dot, with: .color(RGBA.white.alpha(opacity * 0.85).color))
        }
    }
}

private func lightningPoint(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
    CGPoint(x: lerp(Double(a.x), Double(b.x), u), y: lerp(Double(a.y), Double(b.y), u))
}

private func lightningRimPoint(_ pad: CGRect, _ side: Int, _ u: Double, _ inset: Double) -> CGPoint {
    let x: Double = side < 0 ? Double(pad.minX) + inset : Double(pad.maxX) - inset
    let s: Double = 1 - abs(2 * u - 1)
    let y: Double = lerp(Double(pad.minY) + 25, Double(pad.maxY) - 15, u)
    return CGPoint(x: x + Double(side) * 6 * s, y: y)
}

private func lightningChannel(_ a: CGPoint, _ b: CGPoint, _ steps: Int, _ width: Double, _ salt: Int,
                               _ seed: UInt32) -> [CGPoint] {
    let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
    let length = max(1, hypot(dx, dy))
    let nx: Double = -dy / length, ny: Double = dx / length
    var points = [a]
    for i in 1..<steps {
        let u: Double = Double(i) / Double(steps)
        let p = lightningPoint(a, b, u)
        let coarse: Double = (closeNoise(u * 6, Double(salt), seed) - 0.5) * 1.2
        let fine: Double = closeHash(i, salt, seed) - 0.5
        let d: Double = width * sin(Double.pi * u) * (coarse + fine)
        points.append(CGPoint(x: Double(p.x) + nx * d, y: Double(p.y) + ny * d))
    }
    points.append(b)
    return points
}

private func lightningTrace(_ path: inout Path, _ points: [CGPoint], _ first: Double, _ last: Double) {
    if last <= first { return }
    let n = points.count - 1
    let a: Double = first * Double(n), b: Double = last * Double(n)
    let i = Int(a), j = Int(b)
    path.move(to: lightningPoint(points[i], points[i + 1], a - Double(i)))
    if j > i {
        for k in (i + 1)...j { path.addLine(to: points[k]) }
    }
    if j < n { path.addLine(to: lightningPoint(points[j], points[j + 1], b - Double(j))) }
}

private func lightningTube(_ ctx: GraphicsContext, _ path: Path, _ ink: RGBA, _ intensity: Double, _ width: Double) {
    if intensity <= 0 || path.isEmpty { return }
    func line(_ w: Double) -> StrokeStyle { StrokeStyle(lineWidth: CGFloat(w), lineCap: .round, lineJoin: .round) }
    ctx.stroke(path, with: .color(ink.alpha(0.16 * intensity).color), style: line(width * 6))
    ctx.stroke(path, with: .color(ink.alpha(0.65 * intensity).color), style: line(width * 2.6))
    var hot = ctx
    hot.blendMode = .plusLighter
    hot.stroke(path, with: .color(ink.mix(.white, 0.86).alpha(intensity).color), style: line(width))
}

private func lightningHalo(_ ctx: GraphicsContext, _ p: CGPoint, _ r: Double, _ ink: RGBA, _ intensity: Double) {
    if intensity <= 0 { return }
    let box = CGRect(x: Double(p.x) - r, y: Double(p.y) - r, width: r * 2, height: r * 2)
    let colours = Gradient(stops: [
        .init(color: RGBA.white.alpha(intensity * 0.75).color, location: 0),
        .init(color: ink.mix(.white, 0.45).alpha(intensity * 0.45).color, location: 0.15),
        .init(color: ink.alpha(intensity * 0.11).color, location: 0.54),
        .init(color: ink.alpha(0).color, location: 1)
    ])
    ctx.fill(Path(ellipseIn: box), with: .radialGradient(colours, center: p, startRadius: 0, endRadius: CGFloat(r)))
}
