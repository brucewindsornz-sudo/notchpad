import SwiftUI

private let teleportNavy = RGBA(0.08, 0.20, 0.46)
private let teleportBlue = RGBA(0.18, 0.57, 0.99)
private let teleportIce = RGBA(0.56, 0.94, 1)
private let teleportCream = RGBA(1, 0.91, 0.67)

private func teleportLine(_ path: inout Path, _ x: Double, _ y: Double, _ ex: Double, _ ey: Double) {
    path.move(to: CGPoint(x: x, y: y))
    path.addLine(to: CGPoint(x: ex, y: ey))
}

struct TeleportClose: CloseEffectRenderer {
    let duration: Double = 1.04

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let t = f.t
        if t <= 0 { f.drawPad(ctx); return }
        guard t < 1 else { return }
        let tx = Double(f.target.x)
        let ty = f.floating ? Double(f.target.y) : max(Double(f.target.y), Double(f.sink.maxY) - 2)
        let tint = teleportBlue.mix(f.accent, 0.21)
        let bright = teleportIce.mix(f.text, f.dark ? 0.14 : 0.03)
        teleportCurtain(f, ctx, tint, bright)
        teleportCoils(f, ctx, tx, ty, tint)
        teleportGlitter(f, ctx, tx, ty, tint, bright)
        teleportFinish(f, ctx, tx, ty, tint, bright)
    }

    // The rising light takes real pieces of the note with it, one lane at a time.
    private func teleportCurtain(_ f: CloseFrame, _ ctx: GraphicsContext, _ tint: RGBA, _ bright: RGBA) {
        let t = f.t
        guard t < 0.59 else { return }
        let r = f.pad
        let n = 21
        let w = Double(r.width) / Double(n)
        let top = Double(r.minY)
        var intact = Path(), echo = Path(), light = Path(), ribbons = Path()
        var lanes: [CGRect] = []
        for i in 0..<n {
            let x = Double(r.minX) + w * Double(i)
            let q = closeHash(i, 52, f.seed)
            let bow = 0.5 + 0.5 * cos((Double(i) / Double(n) - 0.61) * Double.pi * 2)
            let u = smoothstep(0.018 + bow * 0.039 + q * 0.017, 0.43 + bow * 0.08 + q * 0.035, t)
            let sweep = Double(r.height) * easeOut(u)
            let y = Double(r.maxY) - sweep
            let length = sin(Double.pi * u) * (12 + 31 * q)
            if y > top { intact.addRect(CGRect(x: x, y: top, width: w, height: y - top)) }
            if length <= 0.05 { continue }
            let edge = CGRect(x: x, y: y, width: w, height: min(sweep, 21 + 30 * q))
            echo.addRect(edge)
            lanes.append(edge)
            let a = x + w * (0.28 + 0.31 * q)
            let b = x + w * (0.48 + 0.31 * q)
            teleportLine(&light, a, y - length, a, y + length * (0.8 + q))
            teleportLine(&ribbons, b, y - length * 0.46, b, y + length * 2.5)
        }
        if !intact.isEmpty {
            var solid = ctx
            solid.clip(to: intact)
            f.drawPad(solid)
        }
        guard !echo.isEmpty else { return }
        let glow = smoothstep(0.024, 0.09, t) * (1 - smoothstep(0.37, 0.58, t))
        var ghost = ctx
        ghost.clip(to: f.padPath)
        ghost.clip(to: echo)
        f.drawPad(ghost, opacity: 0.20 * glow)
        let veil = Gradient(stops: [
            .init(color: tint.alpha(0.46 * glow).color, location: 0),
            .init(color: bright.alpha(0.28 * glow).color, location: 0.18),
            .init(color: tint.alpha(0).color, location: 1)
        ])
        for lane in lanes {
            let start = CGPoint(x: lane.minX, y: lane.minY)
            let end = CGPoint(x: lane.minX, y: lane.maxY)
            ghost.fill(Path(lane), with: .linearGradient(veil, startPoint: start, endPoint: end))
        }
        ctx.stroke(ribbons, with: .color(teleportNavy.alpha(0.32 * glow).color), lineWidth: 5.5)
        ctx.stroke(ribbons, with: .color(tint.alpha(0.57 * glow).color), lineWidth: 3.2)
        ctx.stroke(light, with: .color(bright.alpha(0.92 * glow).color), lineWidth: 1.35)
    }

    private func teleportCoils(_ f: CloseFrame, _ ctx: GraphicsContext, _ tx: Double, _ ty: Double, _ tint: RGBA) {
        let q = phase(f.t, 0.27, 0.78)
        guard q > 0 && q < 1 else { return }
        let fade = sin(Double.pi * q)
        let radii = min(164, Double(f.pad.width) * 0.33) * (1 - easeInOut(q))
        let stretch = Double(f.pad.height) * (1 - easeInOut(q))
        var paths = [Path(), Path()]
        for i in 0..<6 {
            let index = Double(i)
            let span = 0.8 + closeHash(i, 85, f.seed) * 1.1
            let offset = f.floating ? (index - 2.5) * 0.15 : 0.11 + index * 0.087
            for j in 0...12 {
                let u = Double(j) / 12
                let a = index * 1.94 + q * 8 + u * span
                let x = tx + sin(a) * radii * (0.55 + 0.09 * index)
                let y = ty + stretch * (offset + cos(a) * 0.065 - u * 0.13)
                let p = CGPoint(x: x, y: y)
                if j == 0 { paths[i % 2].move(to: p) } else { paths[i % 2].addLine(to: p) }
            }
        }
        ctx.stroke(paths[0], with: .color(tint.alpha(fade * 0.35).color), lineWidth: 4.6)
        ctx.stroke(paths[1], with: .color(tint.alpha(fade * 0.44).color), lineWidth: 2.6)
        ctx.stroke(paths[0], with: .color(teleportIce.alpha(fade * 0.64).color), lineWidth: 1.1)
    }

    // Metallic grains keep a hint of the note's actual colour, then wind into the beam.
    private func teleportGlitter(_ f: CloseFrame, _ ctx: GraphicsContext, _ tx: Double, _ ty: Double,
                                 _ tint: RGBA, _ bright: RGBA) {
        let t = f.t, r = f.pad
        guard t >= 0.055 && t < 0.93 else { return }
        let m = f.cells
        var glints = Path(), glows = Path(), tails = Path()
        let levels = 8
        var grains = Array(repeating: Path(), count: 3 * levels)
        let materials = [f.bg.mix(bright, 0.80), f.text.mix(bright, 0.80), f.bg.mix(teleportCream, 0.81)]
        for i in 0..<310 {
            let rx = closeHash(i, 1, f.seed), ry = closeHash(i, 2, f.seed)
            let c = m.color(Int(rx * Double(m.cols)), Int(ry * Double(m.rows)))
            if c.a < 0.17 { continue }
            let q = closeHash(i, 3, f.seed), d = closeHash(i, 4, f.seed)
            let start = 0.056 + 0.29 * (1 - ry) + q * 0.102
            let end = 0.61 + 0.31 * d
            if t <= start || t >= end { continue }
            let v = phase(t, start, end)
            let pull = smoothstep(0.16, 0.95, v)
            let turn = (v * (0.83 + d * 0.46) + q) * Double.pi * 2
            let swell = sin(Double.pi * v)
            let cx = Double(r.minX) + Double(r.width) * rx
            let cy = Double(r.minY) + Double(r.height) * ry
            let x = lerp(cx, tx + (q - 0.5) * 6, pull) + sin(turn) * (13 + 51 * q) * swell
            let y = lerp(cy, ty + d * 3, easeInOut(v)) - (12 + 31 * q) * swell
            let silver = 0.33 + 0.67 * pow(0.5 + 0.5 * sin(turn * 3 + Double(i) * 4), 3)
            let a = smoothstep(0, 0.105, v) * (1 - smoothstep(0.77, 1, v)) * silver
            let s = (0.50 + 1.56 * d) * (1 - 0.58 * pull)
            let level = Int((a * Double(levels)).rounded())
            let grain = CGRect(x: x - s, y: y - s * 1.33, width: s * 2, height: s * 2.66)
            if level > 0 {
                let contrast = max(abs(c.r - f.bg.r), abs(c.g - f.bg.g), abs(c.b - f.bg.b))
                let material = i % 9 == 0 ? 2 : (contrast > 0.29 ? 1 : 0)
                grains[material * levels + level - 1].addEllipse(in: grain)
            }
            if i % 5 == 0 && a > 0.21 {
                let tail = 4 + 14 * swell * q
                teleportLine(&tails, x, y + 1, x - cos(turn) * tail * 0.38, y + tail)
            }
            if i % 17 == 0 && a > 0.45 {
                let flare = 1.5 + 3.1 * silver
                glows.addEllipse(in: CGRect(x: x - flare, y: y - flare, width: flare * 2, height: flare * 2))
                teleportLine(&glints, x - flare * 0.61, y, x + flare * 0.61, y)
                teleportLine(&glints, x, y - flare, x, y + flare)
            }
        }
        // Collect small grains of the same brightness into one fill. Hundreds of
        // individual draws cost time even though each grain only covers a few pixels.
        for i in grains.indices where !grains[i].isEmpty {
            let opacity = Double(i % levels + 1) / Double(levels)
            let colour = materials[i / levels].alpha(opacity)
            ctx.fill(grains[i], with: .color(colour.color))
        }
        let envelope = smoothstep(0.08, 0.24, t) * (1 - smoothstep(0.73, 0.93, t))
        ctx.stroke(tails, with: .color(teleportNavy.alpha(0.43 * envelope).color), lineWidth: 2.4)
        ctx.stroke(tails, with: .color(tint.alpha(0.63 * envelope).color), lineWidth: 1.1)
        ctx.fill(glows, with: .color(tint.alpha(0.24 * envelope).color))
        ctx.stroke(glints, with: .color(teleportCream.alpha(0.94 * envelope).color), lineWidth: 0.9)
    }

    private func teleportFinish(_ f: CloseFrame, _ ctx: GraphicsContext, _ tx: Double, _ ty: Double,
                                _ tint: RGBA, _ bright: RGBA) {
        let t = f.t
        let shaft = smoothstep(0.42, 0.66, t) * (1 - smoothstep(0.78, 0.92, t))
        if shaft > 0 {
            let pinch = smoothstep(0.60, 0.90, t)
            let length = lerp(Double(f.pad.height) * (f.floating ? 0.71 : 0.84), 4, pinch)
            let w = lerp(23, 1.5, pinch)
            let y = f.floating ? ty - length * 0.49 : ty - 4
            let x0 = CGPoint(x: tx - w, y: y), x1 = CGPoint(x: tx + w, y: y)
            let veil = Gradient(stops: [
                .init(color: tint.alpha(0).color, location: 0), .init(color: tint.alpha(0.42 * shaft).color, location: 0.35),
                .init(color: bright.alpha(0.79 * shaft).color, location: 0.5),
                .init(color: tint.alpha(0.42 * shaft).color, location: 0.65), .init(color: tint.alpha(0).color, location: 1)
            ])
            let column = Path(ellipseIn: CGRect(x: tx - w, y: y, width: 2 * w, height: length))
            ctx.fill(column, with: .linearGradient(veil, startPoint: x0, endPoint: x1))
            var line = Path()
            teleportLine(&line, tx, y + length * 0.12, tx, y + length * 0.89)
            ctx.stroke(line, with: .color(teleportNavy.alpha(0.53 * shaft).color), lineWidth: 2.4)
            let core = bright.mix(RGBA.white, 0.37)
            ctx.stroke(line, with: .color(core.alpha(0.94 * shaft).color), lineWidth: 1.1)
        }
        let flash = smoothstep(0.75, 0.82, t) * (1 - smoothstep(0.83, 0.99, t))
        guard flash > 0 else { return }
        let radius = 34 * flash + 8
        let c = tint.alpha(flash * 0.86)
        let bloom = Gradient(stops: [
            .init(color: c.color, location: 0), .init(color: c.alpha(c.a * 0.38).color, location: 0.35),
            .init(color: c.alpha(0).color, location: 1)
        ])
        let halo = Path(ellipseIn: CGRect(x: tx - radius, y: ty - radius, width: radius * 2, height: radius * 2))
        ctx.fill(halo, with: .radialGradient(bloom, center: CGPoint(x: tx, y: ty), startRadius: 0, endRadius: radius))
        let x = lerp(11, 45, easeOut(phase(t, 0.78, 0.92)))
        var line = Path(), core = Path()
        teleportLine(&line, tx - x, ty, tx + x, ty)
        teleportLine(&core, tx - x * 0.37, ty, tx + x * 0.37, ty)
        teleportLine(&core, tx, ty - x * 0.22, tx, ty + x * 0.22)
        ctx.stroke(line, with: .color(teleportNavy.alpha(0.64 * flash).color), lineWidth: 2.7)
        ctx.stroke(line, with: .color(teleportIce.alpha(0.84 * flash).color), lineWidth: 1.3)
        ctx.stroke(core, with: .color(RGBA.white.alpha(flash).color), lineWidth: 1.6)
    }
}
