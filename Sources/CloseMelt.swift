import SwiftUI

// PLACEHOLDER for the "melt" closing animation: the sample effect, so the app builds until the real one lands.
// The pad lifts into the notch while cells of it fly off as sparks.
struct MeltClose: CloseEffectRenderer {
    let duration: Double = 0.8

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let lift: Double = easeIn(phase(f.t, 0.0, 0.8))               // stage 1: 0 → 0.8 of the run
        // The pad, squeezed towards the sink.
        let r = CGRect(x: lerp(f.pad.minX, f.sink.minX, lift), y: lerp(f.pad.minY, f.sink.minY, lift),
                       width: lerp(f.pad.width, f.sink.width, lift), height: lerp(f.pad.height, f.sink.height, lift))
        f.drawPad(ctx, in: r, opacity: 1 - phase(f.t, 0.6, 0.8))
        // A glow line along the bottom edge.
        let glow: Double = sin(Double.pi * phase(f.t, 0.0, 0.8))
        var g = ctx                                                    // a copy = ctx.save() … ctx.restore()
        g.blendMode = .plusLighter
        g.addFilter(.blur(radius: 6))
        g.fill(Path(CGRect(x: r.minX, y: r.maxY - 3, width: r.width, height: 6)), with: .color(f.accent.alpha(0.8 * glow).color))
        // Sparks: every 5th cell of the pad picture flies off, in its own colour.
        var rng = CloseRNG(f.seed)
        var row = 0
        while row < f.cells.rows {
            var col = 0
            while col < f.cells.cols {
                let angle: Double = rng.range(0, Double.pi * 2)
                let speed: Double = rng.range(40, 160)
                let start: Double = rng.range(0, 0.4)
                let c: RGBA = f.cells.color(col, row)
                col += 5
                if c.a <= 0 { continue }
                let life: Double = phase(f.t, start, start + 0.5)
                if life <= 0 || life >= 1 { continue }
                let cell: CGRect = f.cells.rect(col - 5, row)
                let x: Double = Double(cell.midX) + cos(angle) * speed * easeOut(life)
                let y: Double = Double(cell.midY) + sin(angle) * speed * easeOut(life) + 60 * life * life
                ctx.fill(Path(CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)),
                         with: .color(c.mix(f.accent, life).alpha(1 - life).color))
            }
            row += 5
        }
    }
}
