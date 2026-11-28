import SwiftUI

private struct HyperspaceStreak {
    let x0: Double
    let y0: Double
    let x1: Double
    let y1: Double
    let wHead: Double
    let wTail: Double
    let color: RGBA
}

private func hyperspaceTaperedStreak(_ p: inout Path, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                                     _ wHead: Double, _ wTail: Double) {
    let dx: Double = x1 - x0
    let dy: Double = y1 - y0
    let len: Double = hypot(dx, dy)
    if len < 0.5 { return }
    let nx: Double = -dy / len
    let ny: Double = dx / len
    // Shoulder sits 80% of the way toward the leading head for a sleek needle profile.
    let sx: Double = x0 + dx * 0.80
    let sy: Double = y0 + dy * 0.80
    p.move(to: CGPoint(x: x0 + nx * wTail, y: y0 + ny * wTail))
    p.addLine(to: CGPoint(x: sx + nx * wHead, y: sy + ny * wHead))
    p.addLine(to: CGPoint(x: x1, y: y1))
    p.addLine(to: CGPoint(x: sx - nx * wHead, y: sy - ny * wHead))
    p.addLine(to: CGPoint(x: x0 - nx * wTail, y: y0 - ny * wTail))
    p.closeSubpath()
}

private func hyperspaceDiamondFlare(_ p: inout Path, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) {
    if rx <= 0.2 || ry <= 0.2 { return }
    p.move(to: CGPoint(x: cx - rx, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy - ry), control: CGPoint(x: cx - rx * 0.13, y: cy - ry * 0.13))
    p.addQuadCurve(to: CGPoint(x: cx + rx, y: cy), control: CGPoint(x: cx + rx * 0.13, y: cy - ry * 0.13))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy + ry), control: CGPoint(x: cx + rx * 0.13, y: cy + ry * 0.13))
    p.addQuadCurve(to: CGPoint(x: cx - rx, y: cy), control: CGPoint(x: cx - rx * 0.13, y: cy + ry * 0.13))
    p.closeSubpath()
}

/// Hyperspace closing animation: the pad pulls radially into the vanishing point while its pixels
/// stretch into star-lines, triggering an anamorphic jump flash and a receding pinpoint of light.
struct HyperspaceClose: CloseEffectRenderer {
    let duration: Double = 0.95

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let vpX: Double = Double(f.target.x)
        let vpY: Double = Double(f.target.y)
        let padW: Double = Double(f.pad.width)
        let padH: Double = Double(f.pad.height)
        let padMidX: Double = Double(f.pad.midX)
        let padMidY: Double = Double(f.pad.midY)
        let padMinY: Double = Double(f.pad.minY)
        let maxR: Double = hypot(padW, padH) * 0.80

        // Iconic hyperspace palette tinted with theme accent, plus a rich cobalt-indigo backing
        // so light themes and white desktops keep luminous, colourful contrast.
        let warpBlue: RGBA = RGBA(0.24, 0.66, 1.0, 1.0).mix(f.accent, 0.22)
        let warpCobalt: RGBA = RGBA(0.10, 0.34, 0.78, 1.0).mix(f.accent, 0.18)
        let warpCyan: RGBA = RGBA(0.56, 0.90, 1.0, 1.0).mix(f.accent, 0.12)
        let warpCore: RGBA = RGBA(0.96, 0.99, 1.0, 1.0)
        let warpDeep: RGBA = f.dark ? RGBA(0.05, 0.14, 0.36, 1.0) : warpCobalt
        let backingStrength: Double = f.dark ? 0.30 : 0.58

        // --- Stage 1 & 2: The pad itself pulling and smearing into the vanishing point ---
        let pullRaw: Double = phase(f.t, 0.0, 0.50)
        let pull: Double = easeIn(pullRaw)
        let padAlpha: Double = 1.0 - smoothstep(0.28, 0.47, f.t)

        if padAlpha > 0.002 {
            let echoStrength: Double = sin(Double.pi * phase(f.t, 0.01, 0.48))
            if echoStrength > 0.01 {
                for k in stride(from: 5, through: 1, by: -1) {
                    let leadT: Double = clamp01(pullRaw + Double(k) * 0.036)
                    let lead: Double = easeIn(leadT)
                    let sx: Double = lerp(1.0, 0.06, lead)
                    let sy: Double = lerp(1.0, f.floating ? 0.06 : 0.09, lead * 0.94)
                    let ew: Double = padW * sx
                    let eh: Double = padH * sy
                    let ex: Double = lerp(padMidX, vpX, lead) - ew * 0.5
                    let ey: Double = f.floating
                        ? lerp(padMidY, vpY, lead) - eh * 0.5
                        : lerp(padMinY, max(0.0, vpY - eh * 0.35), lead)
                    let er = CGRect(x: ex, y: ey, width: ew, height: eh)
                    let ePath: Path = f.padPath(in: er)
                    let eOp: Double = (0.24 / Double(k)) * echoStrength * padAlpha

                    var eg = ctx
                    eg.clip(to: ePath)
                    f.drawPad(eg, in: er, opacity: eOp)
                    eg.fill(ePath, with: .color(warpBlue.alpha(eOp * 0.55).color))
                }
            }

            let sx: Double = lerp(1.0, 0.05, pull)
            let sy: Double = lerp(1.0, f.floating ? 0.05 : 0.08, pull * 0.94)
            let curW: Double = padW * sx
            let curH: Double = padH * sy
            let curX: Double = lerp(padMidX, vpX, pull) - curW * 0.5
            let curY: Double = f.floating
                ? lerp(padMidY, vpY, pull) - curH * 0.5
                : lerp(padMinY, max(0.0, vpY - curH * 0.35), pull)
            let curRect = CGRect(x: curX, y: curY, width: curW, height: curH)
            let curPath: Path = f.padPath(in: curRect)

            var pg = ctx
            pg.clip(to: curPath)
            f.drawPad(pg, in: curRect, opacity: padAlpha)

            let wash: Double = smoothstep(0.02, 0.36, f.t) * padAlpha
            if wash > 0.01 {
                var wg = pg
                wg.blendMode = f.dark ? .plusLighter : .normal
                let washMidA: Double = (f.dark ? 0.32 : 0.22) * wash
                let washEdgeA: Double = (f.dark ? 0.72 : 0.45) * wash
                let washCenter = CGPoint(x: curX + curW * 0.5, y: f.floating ? curY + curH * 0.5 : curY + curH * 0.14)
                let washGrad = Gradient(stops: [
                    .init(color: warpBlue.alpha(0.0).color, location: 0.0),
                    .init(color: warpBlue.alpha(washMidA).color, location: 0.58),
                    .init(color: warpCyan.alpha(washEdgeA).color, location: 1.0)
                ])
                wg.fill(curPath, with: .radialGradient(washGrad, center: washCenter, startRadius: 0, endRadius: max(curW, curH) * 0.72))
            }

            let rim: Double = sin(Double.pi * phase(f.t, 0.0, 0.38))
            if rim > 0.01 {
                ctx.stroke(curPath, with: .color(warpDeep.alpha(backingStrength * 0.55 * rim).color), lineWidth: 2.8)
                var rg = ctx
                rg.blendMode = .plusLighter
                rg.stroke(curPath, with: .color(warpCyan.alpha(0.75 * rim).color), lineWidth: 1.4)
            }
        }

        // --- Early vanishing-point ignition glint ---
        let charge: Double = sin(Double.pi * phase(f.t, 0.0, 0.44))
        if charge > 0.01 {
            let cr: Double = lerp(5.0, 24.0, charge)
            var cg = ctx
            cg.blendMode = f.dark ? .plusLighter : .normal
            let chargeGrad = Gradient(stops: [
                .init(color: warpCore.alpha(0.75 * charge).color, location: 0.0),
                .init(color: warpBlue.alpha(0.38 * charge).color, location: 0.45),
                .init(color: warpBlue.alpha(0.0).color, location: 1.0)
            ])
            let chargeRect = CGRect(x: vpX - cr, y: vpY - cr * 0.65, width: cr * 2.0, height: cr * 1.3)
            cg.fill(Path(ellipseIn: chargeRect), with: .radialGradient(chargeGrad, center: CGPoint(x: vpX, y: vpY), startRadius: 0, endRadius: cr))
            var spark = Path()
            hyperspaceDiamondFlare(&spark, vpX, vpY, lerp(6.0, 46.0, charge), lerp(1.0, 2.8, charge))
            hyperspaceDiamondFlare(&spark, vpX, vpY, lerp(1.0, 2.2, charge), lerp(4.0, 18.0, charge))
            cg.fill(spark, with: .color(warpCore.alpha(0.70 * charge).color))
        }

        // --- Stage 2 & 3: Star-lines born from the pad's own cells ---
        var cellBackPath = Path()
        var cellCorePath = Path()
        var streaks: [HyperspaceStreak] = []
        streaks.reserveCapacity(320)
        let cellStep = 3
        let seed17: UInt32 = f.seed &+ 17
        let seed53: UInt32 = f.seed &+ 53
        let targetHue: RGBA = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.55)

        var row = 0
        while row < f.cells.rows {
            var col = 0
            while col < f.cells.cols {
                let curCol = col
                col += cellStep
                let c: RGBA = f.cells.color(curCol, row)
                if c.a <= 0.05 { continue }

                let h0: Double = closeHash(curCol, row, f.seed)
                let h1: Double = closeHash(curCol, row, seed17)
                let h2: Double = closeHash(curCol, row, seed53)

                let contrast: Double = abs(c.r - f.bg.r) + abs(c.g - f.bg.g) + abs(c.b - f.bg.b)
                let isText: Bool = contrast > 0.20
                if !isText && h2 < 0.36 { continue }

                let cell: CGRect = f.cells.rect(curCol, row)
                let dx: Double = Double(cell.midX) - vpX
                let dy: Double = Double(cell.midY) - vpY
                let dist: Double = hypot(dx, dy)
                if dist < 6.0 { continue }

                let ux: Double = dx / dist
                let uy: Double = dy / dist
                let normDist: Double = clamp01(dist / maxR)

                let rawStart: Double = lerp(0.005, 0.17, h0) + (1.0 - normDist) * 0.07 - (isText ? 0.025 : 0.0)
                let start: Double = max(0.005, rawStart)
                let lifeDur: Double = lerp(0.36, 0.52, h1)
                let u: Double = phase(f.t, start, start + lifeDur)
                if u <= 0.0 || u >= 1.0 { continue }

                let kick: Double = sin(Double.pi * clamp01(u / 0.34)) * lerp(26.0, 92.0, h1) * (0.35 + 0.65 * normDist)
                let headProgress: Double = easeIn(clamp01(u * 1.18))
                let tailProgress: Double = easeIn(phase(u, 0.14, 1.0))

                let headR: Double = max(0.0, dist * (1.0 - headProgress))
                let tailR: Double = max(headR + 2.5, (dist + kick) * (1.0 - tailProgress))

                let x0: Double = vpX + ux * tailR
                let y0: Double = vpY + uy * tailR
                let x1: Double = vpX + ux * headR
                let y1: Double = vpY + uy * headR

                let fade: Double = sin(Double.pi * clamp01(u)) * (1.0 - smoothstep(0.64, 0.78, f.t))
                if fade <= 0.01 { continue }

                let isHero: Bool = isText || h2 > 0.74
                let baseW: Double = isHero ? lerp(1.4, 2.8, h2) : lerp(0.8, 1.5, h2)
                let wHead: Double = baseW * (0.45 + 0.55 * fade)
                let wTail: Double = wHead * 0.16

                let blueShift: Double = smoothstep(0.12, 0.76, u)
                let coreMix: Double = f.dark ? blueShift * 0.36 : blueShift * 0.18
                let baseColor: RGBA = c.mix(targetHue, blueShift * 0.76).mix(warpCore, coreMix)

                if isHero {
                    hyperspaceTaperedStreak(&cellBackPath, x0, y0, x1, y1, wHead * 1.35, wTail * 1.25)
                    let cx0: Double = x0 + (x1 - x0) * 0.30
                    let cy0: Double = y0 + (y1 - y0) * 0.30
                    hyperspaceTaperedStreak(&cellCorePath, cx0, cy0, x1, y1, wHead * 0.50, 0.15)
                }

                let alpha: Double = fade * (isHero ? 0.94 : 0.76)
                streaks.append(HyperspaceStreak(x0: x0, y0: y0, x1: x1, y1: y1, wHead: wHead, wTail: wTail, color: baseColor.alpha(alpha)))
            }
            row += cellStep
        }

        let streakPresence: Double = sin(Double.pi * phase(f.t, 0.01, 0.74))
        if !cellBackPath.isEmpty && streakPresence > 0.01 {
            let backA: Double = (f.dark ? 0.22 : 0.36) * streakPresence
            ctx.fill(cellBackPath, with: .color(warpDeep.alpha(backA).color))
        }
        for s in streaks {
            var sp = Path()
            hyperspaceTaperedStreak(&sp, s.x0, s.y0, s.x1, s.y1, s.wHead, s.wTail)
            ctx.fill(sp, with: .color(s.color.color))
        }
        if !cellCorePath.isEmpty && streakPresence > 0.01 {
            var cg = ctx
            cg.blendMode = .plusLighter
            let coreA: Double = (f.dark ? 0.72 : 0.85) * streakPresence
            cg.fill(cellCorePath, with: .color(warpCore.alpha(coreA).color))
        }

        // --- Dedicated cinematic hyperspace tunnel star-lines ---
        let tunnelFade: Double = sin(Double.pi * phase(f.t, 0.03, 0.74))
        if tunnelFade > 0.01 {
            var rayBack = Path()
            var rayBlue = Path()
            var rayCore = Path()
            let rayCount = 72

            for i in 0..<rayCount {
                let h0: Double = closeHash(i, 101, f.seed)
                let h1: Double = closeHash(i, 211, f.seed)
                let h2: Double = closeHash(i, 307, f.seed)

                let frac: Double = (Double(i) + h0) / Double(rayCount)
                let angle: Double = f.floating
                    ? (Double(i) / Double(rayCount)) * Double.pi * 2.0 + (h0 - 0.5) * 0.09
                    : lerp(0.05, Double.pi - 0.05, frac)

                let start: Double = lerp(0.02, 0.20, h1)
                let dur: Double = lerp(0.36, 0.50, h2)
                let u: Double = phase(f.t, start, start + dur)
                if u <= 0.0 || u >= 1.0 { continue }

                let reach: Double = lerp(maxR * 0.45, maxR * 1.18, h0)
                let stretchOut: Double = sin(Double.pi * clamp01(u / 0.36)) * lerp(38.0, 115.0, h2)
                let headR: Double = max(0.0, reach * (1.0 - easeIn(clamp01(u * 1.20))))
                let tailR: Double = max(headR + 4.0, (reach + stretchOut) * (1.0 - easeIn(phase(u, 0.16, 1.0))))

                let ux: Double = cos(angle)
                let uy: Double = sin(angle)
                let x0: Double = vpX + ux * tailR
                let y0: Double = vpY + uy * tailR
                let x1: Double = vpX + ux * headR
                let y1: Double = vpY + uy * headR

                let w: Double = lerp(0.95, 2.7, h2 * h2) * sin(Double.pi * u)
                hyperspaceTaperedStreak(&rayBack, x0, y0, x1, y1, w * 1.38, w * 0.25)
                hyperspaceTaperedStreak(&rayBlue, x0, y0, x1, y1, w * 1.15, w * 0.18)
                let cx0: Double = x0 + (x1 - x0) * 0.36
                let cy0: Double = y0 + (y1 - y0) * 0.36
                hyperspaceTaperedStreak(&rayCore, cx0, cy0, x1, y1, w * 0.54, 0.14)
            }

            if !rayBack.isEmpty {
                let backA: Double = (f.dark ? 0.24 : 0.38) * tunnelFade
                ctx.fill(rayBack, with: .color(warpDeep.alpha(backA).color))
            }
            if !rayBlue.isEmpty {
                var bg = ctx
                bg.blendMode = f.dark ? .plusLighter : .normal
                let rayHue: RGBA = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.65)
                bg.fill(rayBlue, with: .color(rayHue.alpha(0.86 * tunnelFade).color))
            }
            if !rayCore.isEmpty {
                var cg = ctx
                cg.blendMode = .plusLighter
                cg.fill(rayCore, with: .color(warpCore.alpha(0.90 * tunnelFade).color))
            }
        }

        // --- Stage 4: Jump flash, soft energy wave & anamorphic lens flare ---
        let flashRise: Double = easeOut(phase(f.t, 0.42, 0.56))
        let flashFall: Double = 1.0 - easeOut(phase(f.t, 0.56, 0.80))
        let flash: Double = flashRise * flashFall

        let ringT: Double = phase(f.t, 0.48, 0.74)
        if ringT > 0.0 && ringT < 1.0 {
            let outerR: Double = lerp(12.0, f.floating ? 124.0 : 92.0, easeOut(ringT))
            let innerR: Double = max(0.0, outerR * lerp(0.45, 0.78, ringT))
            let ringFade: Double = sin(Double.pi * ringT) * (1.0 - ringT * 0.45)
            let waveRect = CGRect(x: vpX - outerR, y: vpY - outerR, width: outerR * 2.0, height: outerR * 2.0)

            var wg = ctx
            wg.blendMode = f.dark ? .plusLighter : .normal
            let waveGrad = Gradient(stops: [
                .init(color: warpBlue.alpha(0.0).color, location: 0.0),
                .init(color: warpBlue.alpha(0.0).color, location: clamp01(innerR / outerR)),
                .init(color: warpCyan.alpha((f.dark ? 0.50 : 0.36) * ringFade).color, location: 0.88),
                .init(color: warpCore.alpha((f.dark ? 0.72 : 0.45) * ringFade).color, location: 0.96),
                .init(color: warpBlue.alpha(0.0).color, location: 1.0)
            ])
            wg.fill(Path(ellipseIn: waveRect), with: .radialGradient(waveGrad, center: CGPoint(x: vpX, y: vpY), startRadius: 0, endRadius: outerR))
        }

        let glintT: Double = phase(f.t, 0.54, 0.97)
        let glintAlpha: Double = (glintT > 0.0 && glintT < 1.0)
            ? (1.0 - easeIn(glintT)) * smoothstep(0.54, 0.60, f.t)
            : 0.0
        let bloomLevel: Double = max(flash, glintAlpha * 0.52)

        if bloomLevel > 0.01 {
            var bloomCtx = ctx
            if !testNoEffects {
                bloomCtx.addFilter(.blur(radius: 12))
            }
            bloomCtx.drawLayer { layer in
                let darkR: Double = lerp(14.0, 70.0, flash) + glintAlpha * 10.0
                let darkRect = CGRect(x: vpX - darkR, y: vpY - darkR * 0.70, width: darkR * 2.0, height: darkR * 1.40)
                layer.fill(Path(ellipseIn: darkRect), with: .color(warpDeep.alpha(backingStrength * 0.92 * bloomLevel).color))

                let glowR: Double = lerp(10.0, 62.0, flash) + glintAlpha * 16.0
                let glowRect = CGRect(x: vpX - glowR, y: vpY - glowR * 0.70, width: glowR * 2.0, height: glowR * 1.40)
                layer.fill(Path(ellipseIn: glowRect), with: .color(warpBlue.alpha(0.88 * bloomLevel).color))

                if flash > 0.02 {
                    let barW: Double = lerp(34.0, 300.0, easeOut(flash))
                    let barH: Double = lerp(3.0, 12.0, flash)
                    let barRect = CGRect(x: vpX - barW * 0.5, y: vpY - barH * 0.5, width: barW, height: barH)
                    layer.fill(Path(ellipseIn: barRect), with: .color(warpCyan.alpha(0.84 * flash).color))
                }
            }
        }

        if flash > 0.01 {
            let flareW: Double = lerp(20.0, 290.0, easeOut(flash))
            let flareH: Double = lerp(2.0, 9.2, flash)
            let vertH: Double = lerp(8.0, f.floating ? 64.0 : 34.0, flash)

            var flareBack = Path()
            hyperspaceDiamondFlare(&flareBack, vpX, vpY, flareW * 1.02, flareH * 1.45)
            ctx.fill(flareBack, with: .color(warpDeep.alpha(backingStrength * 0.72 * flash).color))

            var fg = ctx
            fg.blendMode = f.dark ? .plusLighter : .normal
            var horiz = Path()
            hyperspaceDiamondFlare(&horiz, vpX, vpY, flareW, flareH)
            fg.fill(horiz, with: .color(warpCyan.alpha(0.90 * flash).color))

            var vert = Path()
            hyperspaceDiamondFlare(&vert, vpX, vpY, flareH * 0.85, vertH)
            fg.fill(vert, with: .color(warpCyan.alpha(0.78 * flash).color))

            var cg = ctx
            cg.blendMode = .plusLighter
            var core = Path()
            hyperspaceDiamondFlare(&core, vpX, vpY, flareW * 0.56, flareH * 0.50)
            hyperspaceDiamondFlare(&core, vpX, vpY, flareH * 0.45, vertH * 0.56)
            cg.fill(core, with: .color(warpCore.alpha(0.98 * flash).color))

            let orbR: Double = lerp(4.0, 24.0, flash)
            let orbRect = CGRect(x: vpX - orbR, y: vpY - orbR, width: orbR * 2.0, height: orbR * 2.0)
            let orbGrad = Gradient(stops: [
                .init(color: warpCore.alpha(0.98 * flash).color, location: 0.0),
                .init(color: warpCyan.alpha(0.68 * flash).color, location: 0.45),
                .init(color: warpBlue.alpha(0.0).color, location: 1.0)
            ])
            cg.fill(Path(ellipseIn: orbRect), with: .radialGradient(orbGrad, center: CGPoint(x: vpX, y: vpY), startRadius: 0, endRadius: orbR))
        }

        // --- Stage 5: Receding point of light & final trailing micro-wisps ---
        if glintAlpha > 0.01 {
            var latePath = Path()
            for i in 0..<10 {
                let h0: Double = closeHash(i, 701, f.seed)
                let h1: Double = closeHash(i, 809, f.seed)
                let angle: Double = f.floating
                    ? (Double(i) / 10.0) * Double.pi * 2.0 + h0 * 0.5
                    : lerp(0.18, Double.pi - 0.18, (Double(i) + h0) / 10.0)
                let st: Double = lerp(0.56, 0.72, h1)
                let u: Double = phase(f.t, st, st + 0.22)
                if u <= 0.0 || u >= 1.0 { continue }
                let startR: Double = lerp(42.0, 95.0, h0)
                let headR: Double = startR * (1.0 - easeIn(clamp01(u * 1.25)))
                let tailR: Double = max(headR + 2.0, startR * (1.0 - easeIn(phase(u, 0.15, 1.0))))
                let ux: Double = cos(angle)
                let uy: Double = sin(angle)
                hyperspaceTaperedStreak(&latePath, vpX + ux * tailR, vpY + uy * tailR, vpX + ux * headR, vpY + uy * headR, 1.15, 0.15)
            }
            if !latePath.isEmpty {
                var lg = ctx
                lg.blendMode = f.dark ? .plusLighter : .normal
                lg.fill(latePath, with: .color(warpCyan.alpha(0.75 * glintAlpha).color))
            }

            let starScale: Double = 1.0 - easeIn(glintT)
            let armX: Double = lerp(0.6, 32.0, starScale)
            let armY: Double = lerp(0.6, 15.0, starScale)
            let coreR: Double = lerp(0.5, 5.4, starScale)

            var starBack = Path()
            hyperspaceDiamondFlare(&starBack, vpX, vpY, armX * 1.12, 3.4 * starScale + 0.7)
            hyperspaceDiamondFlare(&starBack, vpX, vpY, 3.4 * starScale + 0.7, armY * 1.12)
            ctx.fill(starBack, with: .color(warpDeep.alpha(backingStrength * 0.85 * glintAlpha).color))

            var sg = ctx
            sg.blendMode = .plusLighter
            var star = Path()
            hyperspaceDiamondFlare(&star, vpX, vpY, armX, 2.2 * starScale + 0.4)
            hyperspaceDiamondFlare(&star, vpX, vpY, 2.2 * starScale + 0.4, armY)
            sg.fill(star, with: .color(warpCore.alpha(0.96 * glintAlpha).color))
            let coreRect = CGRect(x: vpX - coreR, y: vpY - coreR, width: coreR * 2.0, height: coreR * 2.0)
            sg.fill(Path(ellipseIn: coreRect), with: .color(warpCore.alpha(glintAlpha).color))
        }
    }
}
