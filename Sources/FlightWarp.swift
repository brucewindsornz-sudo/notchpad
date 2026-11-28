import SwiftUI

private struct WarpCellStreak {
    let x0: Double
    let y0: Double
    let x1: Double
    let y1: Double
    let w: Double
    let color: RGBA
}

private func warpTaperedStreak(_ p: inout Path, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                               _ wHead: Double, _ wTail: Double) {
    let dx: Double = x1 - x0
    let dy: Double = y1 - y0
    let len: Double = hypot(dx, dy)
    if len < 0.5 { return }
    let nx: Double = -dy / len
    let ny: Double = dx / len
    let sx: Double = x0 + dx * 0.80
    let sy: Double = y0 + dy * 0.80
    p.move(to: CGPoint(x: x0 + nx * wTail, y: y0 + ny * wTail))
    p.addLine(to: CGPoint(x: sx + nx * wHead, y: sy + ny * wHead))
    p.addLine(to: CGPoint(x: x1, y: y1))
    p.addLine(to: CGPoint(x: sx - nx * wHead, y: sy - ny * wHead))
    p.addLine(to: CGPoint(x: x0 - nx * wTail, y: y0 - ny * wTail))
    p.closeSubpath()
}

private func warpDiamondFlare(_ p: inout Path, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) {
    if rx <= 0.2 || ry <= 0.2 { return }
    p.move(to: CGPoint(x: cx - rx, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy - ry), control: CGPoint(x: cx - rx * 0.14, y: cy - ry * 0.14))
    p.addQuadCurve(to: CGPoint(x: cx + rx, y: cy), control: CGPoint(x: cx + rx * 0.14, y: cy - ry * 0.14))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy + ry), control: CGPoint(x: cx + rx * 0.14, y: cy + ry * 0.14))
    p.addQuadCurve(to: CGPoint(x: cx - rx, y: cy), control: CGPoint(x: cx - rx * 0.14, y: cy + ry * 0.14))
    p.closeSubpath()
}

private func warpDrawDirectionalPad(_ f: FlightFrame, _ ctx: GraphicsContext, _ cx: Double, _ cy: Double,
                                    _ theta: Double, _ stretchX: Double, _ pinchY: Double, _ opacity: Double,
                                    _ leadGlow: Double, _ warpBlue: RGBA, _ warpCyan: RGBA, _ warpCore: RGBA) {
    if opacity <= 0.002 { return }
    let fromMidX: Double = Double(f.from.midX)
    let fromMidY: Double = Double(f.from.midY)
    let fromPath: Path = f.fromPath

    var g = ctx
    g.translateBy(x: cx, y: cy)
    g.rotate(by: .radians(theta))
    g.scaleBy(x: stretchX, y: pinchY)
    g.rotate(by: .radians(-theta))
    g.translateBy(x: -fromMidX, y: -fromMidY)
    g.clip(to: fromPath)
    f.drawFrom(g, in: f.from, opacity: opacity)

    // Directional leading-edge energy wash: trailing edge stays true to the pad, leading edge burns bright.
    if leadGlow > 0.01 {
        let ux: Double = cos(theta)
        let uy: Double = sin(theta)
        let halfSpan: Double = hypot(Double(f.from.width), Double(f.from.height)) * 0.52
        let p0 = CGPoint(x: fromMidX - ux * halfSpan, y: fromMidY - uy * halfSpan)
        let p1 = CGPoint(x: fromMidX + ux * halfSpan, y: fromMidY + uy * halfSpan)
        var wg = g
        wg.blendMode = f.dark ? .plusLighter : .normal
        let midA: Double = (f.dark ? 0.25 : 0.14) * leadGlow
        let cyanA: Double = (f.dark ? 0.65 : 0.34) * leadGlow
        let coreA: Double = (f.dark ? 0.90 : 0.55) * leadGlow
        let grad = Gradient(stops: [
            .init(color: warpBlue.alpha(0.0).color, location: 0.0),
            .init(color: warpBlue.alpha(midA).color, location: 0.45),
            .init(color: warpCyan.alpha(cyanA).color, location: 0.82),
            .init(color: warpCore.alpha(coreA).color, location: 1.0)
        ])
        wg.fill(fromPath, with: .linearGradient(grad, startPoint: p0, endPoint: p1))
    }
}

/// Warp jump boomerang animation: the pad coils, stretches along its flight path (leading edge first)
/// into a luminous streak, snaps to the notch with a flash and shock ring, and springs back into place.
struct WarpFlight: FlightEffectRenderer {
    let duration: Double = 0.95

    func draw(_ f: FlightFrame, _ ctx: GraphicsContext) {
        let fromCx: Double = Double(f.from.midX)
        let fromCy: Double = Double(f.from.midY)
        let fromW: Double = Double(f.from.width)
        let fromH: Double = Double(f.from.height)
        let toCx: Double = Double(f.to.midX)
        let toCy: Double = Double(f.to.midY)
        let toMinY: Double = Double(f.to.minY)
        let toMaxY: Double = Double(f.to.maxY)
        let toW: Double = Double(f.to.width)
        let toH: Double = Double(f.to.height)

        let dx: Double = toCx - fromCx
        let dy: Double = toCy - fromCy
        let dist: Double = max(1.0, hypot(dx, dy))
        let ux: Double = dx / dist
        let uy: Double = dy / dist
        let vx: Double = -uy
        let vy: Double = ux
        let theta: Double = atan2(dy, dx)

        let warpBlue: RGBA = RGBA(0.22, 0.66, 1.0, 1.0).mix(f.accent, 0.26)
        let warpCobalt: RGBA = RGBA(0.10, 0.34, 0.78, 1.0).mix(f.accent, 0.22)
        let warpCyan: RGBA = RGBA(0.56, 0.92, 1.0, 1.0).mix(f.accent, 0.14)
        let warpCore: RGBA = RGBA(0.96, 0.99, 1.0, 1.0)
        let warpDeep: RGBA = f.dark ? RGBA(0.05, 0.14, 0.36, 1.0) : warpCobalt

        let projLen: Double = max(180.0, abs(fromW * ux) + abs(fromH * uy))
        let projWidth: Double = max(160.0, abs(fromW * vx) + abs(fromH * vy))

        let recoil: Double = sin(Double.pi * phase(f.t, 0.0, 0.14)) * min(22.0, dist * 0.065)
        let leadP: Double = easeInOut(phase(f.t, 0.06, 0.48))
        let tailP: Double = easeIn(phase(f.t, 0.18, 0.53))
        let midP: Double = (leadP + tailP) * 0.5
        let gap: Double = max(0.0, leadP - tailP)

        // --- Stage 1 & 2: Luminous warp corridor ribbon ---
        let bridge: Double = sin(Double.pi * phase(f.t, 0.18, 0.64))
        if bridge > 0.01 {
            let bHeadP: Double = clamp01(leadP * 1.04)
            let bTailP: Double = clamp01(tailP * 0.85)
            let bx0: Double = fromCx + dx * bTailP
            let by0: Double = fromCy + dy * bTailP
            let bx1: Double = fromCx + dx * bHeadP
            let by1: Double = fromCy + dy * bHeadP
            let ribbonW: Double = projWidth * lerp(0.14, 0.30, bridge) * (1.0 - smoothstep(0.46, 0.64, f.t) * 0.65)

            var rb = Path()
            warpTaperedStreak(&rb, bx0, by0, bx1, by1, ribbonW * 0.52, ribbonW * 0.10)
            var rg = ctx
            rg.blendMode = f.dark ? .plusLighter : .normal
            let bGrad = Gradient(stops: [
                .init(color: warpBlue.alpha(0.0).color, location: 0.0),
                .init(color: warpBlue.alpha((f.dark ? 0.38 : 0.24) * bridge).color, location: 0.45),
                .init(color: warpCyan.alpha((f.dark ? 0.68 : 0.42) * bridge).color, location: 0.88),
                .init(color: warpCore.alpha((f.dark ? 0.82 : 0.52) * bridge).color, location: 1.0)
            ])
            rg.fill(rb, with: .linearGradient(bGrad, startPoint: CGPoint(x: bx0, y: by0), endPoint: CGPoint(x: bx1, y: by1)))
        }

        // --- Stage 2: Floating pad stretching into a sleek warp streak ---
        let fromFade: Double = 1.0 - smoothstep(0.42, 0.51, f.t)
        if fromFade > 0.002 {
            let streakRamp: Double = easeIn(phase(f.t, 0.12, 0.50))
            let stretch: Double = min(4.0, 1.0 + (gap * dist * 1.55) / projLen + streakRamp * 0.85)
            let pinch: Double = max(0.24, (1.0 / pow(stretch, 0.62)) * (1.0 - streakRamp * 0.35))
            let curCx: Double = fromCx + dx * midP - ux * recoil
            let curCy: Double = fromCy + dy * midP - uy * recoil

            let echoStrength: Double = sin(Double.pi * phase(f.t, 0.12, 0.51))
            let echoRamp: Double = smoothstep(0.12, 0.28, f.t)
            let leadGlow: Double = smoothstep(0.04, 0.44, f.t)
            if echoStrength > 0.01 && echoRamp > 0.01 {
                for k in stride(from: 4, through: 1, by: -1) {
                    let kd: Double = Double(k)
                    let lagP: Double = clamp01(midP - kd * 0.045 * echoRamp)
                    let eStretch: Double = min(4.2, stretch * (1.0 + kd * 0.08 * echoRamp))
                    let ePinch: Double = max(0.18, pinch * (1.0 - kd * 0.05 * echoRamp))
                    let ex: Double = fromCx + dx * lagP - ux * recoil
                    let ey: Double = fromCy + dy * lagP - uy * recoil
                    let eOp: Double = (0.24 / kd) * echoStrength * fromFade
                    warpDrawDirectionalPad(f, ctx, ex, ey, theta, eStretch, ePinch, eOp, leadGlow * 0.95, warpBlue, warpCyan, warpCore)
                }
            }

            warpDrawDirectionalPad(f, ctx, curCx, curCy, theta, stretch, pinch, fromFade, leadGlow, warpBlue, warpCyan, warpCore)

            let rim: Double = sin(Double.pi * phase(f.t, 0.0, 0.48))
            if rim > 0.01 {
                var rg = ctx
                rg.translateBy(x: curCx, y: curCy)
                rg.rotate(by: .radians(theta))
                rg.scaleBy(x: stretch, y: pinch)
                rg.rotate(by: .radians(-theta))
                rg.translateBy(x: -fromCx, y: -fromCy)
                let fromPath: Path = f.fromPath
                rg.stroke(fromPath, with: .color(warpDeep.alpha((f.dark ? 0.24 : 0.40) * rim).color), lineWidth: 2.8)
                var rg2 = rg
                rg2.blendMode = .plusLighter
                rg2.stroke(fromPath, with: .color(warpCyan.alpha(0.88 * rim).color), lineWidth: 1.5)
            }

            let noseGlow: Double = sin(Double.pi * phase(f.t, 0.10, 0.52))
            if noseGlow > 0.01 {
                let noseDist: Double = projLen * 0.48 * stretch
                let leadLen: Double = min(noseDist, dist * 0.55)
                let trailLen: Double = min(noseDist * 0.65, dist * 0.40)
                let nx: Double = curCx + ux * leadLen
                let ny: Double = curCy + uy * leadLen
                let tx: Double = curCx - ux * trailLen
                let ty: Double = curCy - uy * trailLen
                var lance = Path()
                warpTaperedStreak(&lance, tx, ty, nx, ny, lerp(4.0, 14.0, noseGlow), 1.0)
                var lg = ctx
                lg.blendMode = .plusLighter
                lg.fill(lance, with: .color(warpCore.alpha(0.75 * noseGlow).color))
            }
        }

        // --- Stage 5: Docked pad emerging from the arrival flash with elastic spring-back ---
        let toAppear: Double = smoothstep(0.47, 0.54, f.t)
        if toAppear > 0.002 {
            let settleT: Double = phase(f.t, 0.48, 0.94)
            let spring: Double = settleT < 1.0 ? exp(-6.2 * settleT) * cos(Double.pi * 2.5 * settleT) : 0.0
            let dampEnv: Double = 1.0 - smoothstep(0.82, 0.94, f.t)
            let osc: Double = spring * dampEnv

            let anchorX: Double = toCx
            let anchorY: Double = toMinY + 12.0
            let scaleX: Double = 1.0 - 0.15 * osc
            let scaleY: Double = 1.0 + 0.20 * osc
            let shiftX: Double = -ux * 24.0 * max(0.0, osc)
            let shiftY: Double = -uy * 16.0 * max(0.0, osc)
            let toPath: Path = f.toPath

            var tg = ctx
            tg.translateBy(x: anchorX + shiftX, y: anchorY + shiftY)
            tg.scaleBy(x: scaleX, y: scaleY)
            tg.translateBy(x: -anchorX, y: -anchorY)
            tg.clip(to: toPath)
            f.drawTo(tg, in: f.to, opacity: toAppear)

            let sheenT: Double = phase(f.t, 0.50, 0.80)
            if sheenT > 0.0 && sheenT < 1.0 {
                let sheenAlpha: Double = sin(Double.pi * sheenT) * 0.42
                var sg = tg
                sg.blendMode = f.dark ? .plusLighter : .normal
                let sweepY: Double = lerp(toMinY - 60.0, toMaxY + 60.0, easeOut(sheenT))
                let sheenGrad = Gradient(stops: [
                    .init(color: warpCyan.alpha(0.0).color, location: 0.0),
                    .init(color: warpCyan.alpha(sheenAlpha).color, location: 0.48),
                    .init(color: warpCore.alpha(sheenAlpha * 0.85).color, location: 0.54),
                    .init(color: warpCyan.alpha(0.0).color, location: 1.0)
                ])
                sg.fill(toPath, with: .linearGradient(sheenGrad, startPoint: CGPoint(x: toCx, y: sweepY - 50.0), endPoint: CGPoint(x: toCx, y: sweepY + 50.0)))
            }

            let toRim: Double = sin(Double.pi * phase(f.t, 0.48, 0.76))
            if toRim > 0.01 {
                var rg = ctx
                rg.translateBy(x: anchorX + shiftX, y: anchorY + shiftY)
                rg.scaleBy(x: scaleX, y: scaleY)
                rg.translateBy(x: -anchorX, y: -anchorY)
                rg.blendMode = f.dark ? .plusLighter : .normal
                rg.stroke(toPath, with: .color(warpCyan.alpha(0.75 * toRim).color), lineWidth: 1.8)
            }
        }

        // --- Pad-coloured slipstream streaks & high-speed corridor lines ---
        let wakePresence: Double = sin(Double.pi * phase(f.t, 0.03, 0.74))
        if wakePresence > 0.01 {
            var cellBack = Path()
            var cellCore = Path()
            var cellStreaks: [WarpCellStreak] = []
            cellStreaks.reserveCapacity(160)
            let step = 4
            let seed29: UInt32 = f.seed &+ 29
            let seed71: UInt32 = f.seed &+ 71
            let targetHue: RGBA = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.62)

            var row = 0
            while row < f.fromCells.rows {
                var col = 0
                while col < f.fromCells.cols {
                    let curCol = col
                    col += step
                    let c: RGBA = f.fromCells.color(curCol, row)
                    if c.a <= 0.05 { continue }

                    let h0: Double = closeHash(curCol, row, f.seed)
                    let h1: Double = closeHash(curCol, row, seed29)
                    let h2: Double = closeHash(curCol, row, seed71)

                    let contrast: Double = abs(c.r - f.bg.r) + abs(c.g - f.bg.g) + abs(c.b - f.bg.b)
                    let isText: Bool = contrast > 0.20
                    if !isText && h2 < 0.48 { continue }

                    let cell: CGRect = f.fromCells.rect(curCol, row)
                    let relX: Double = Double(cell.midX) - fromCx
                    let relY: Double = Double(cell.midY) - fromCy

                    let along: Double = relX * ux + relY * uy
                    let across: Double = relX * vx + relY * vy
                    let leadBias: Double = clamp01(0.5 - along / projLen)

                    let start: Double = lerp(0.03, 0.20, h0) + leadBias * 0.07
                    let dur: Double = lerp(0.36, 0.48, h1)
                    let u: Double = phase(f.t, start, start + dur)
                    if u <= 0.0 || u >= 1.0 { continue }

                    let headU: Double = easeInOut(clamp01(u * 1.22))
                    let tailU: Double = easeIn(phase(u, 0.16, 1.0))

                    let sinU: Double = sin(Double.pi * u)
                    let pinchLane: Double = 1.0 - 0.50 * sinU
                    let latX: Double = vx * across * pinchLane
                    let latY: Double = vy * across * pinchLane
                    let alongOffset: Double = along * (1.0 - 0.60 * sinU)

                    let x1: Double = fromCx + dx * headU + latX + ux * alongOffset
                    let y1: Double = fromCy + dy * headU + latY + uy * alongOffset
                    let x0: Double = fromCx + dx * tailU + latX + ux * alongOffset
                    let y0: Double = fromCy + dy * tailU + latY + uy * alongOffset

                    let isHero: Bool = isText || h2 > 0.76
                    let baseW: Double = isHero ? lerp(1.3, 2.5, h2) : lerp(0.8, 1.4, h2)
                    let w: Double = baseW * (0.45 + 0.55 * sinU)

                    let shift: Double = smoothstep(0.12, 0.78, u)
                    let coreMix: Double = f.dark ? shift * 0.42 : shift * 0.18
                    let colColor: RGBA = c.mix(targetHue, shift * 0.74).mix(warpCore, coreMix)

                    if isHero {
                        warpTaperedStreak(&cellBack, x0, y0, x1, y1, w * 1.35, w * 0.25)
                        let cx0: Double = x0 + (x1 - x0) * 0.32
                        let cy0: Double = y0 + (y1 - y0) * 0.32
                        warpTaperedStreak(&cellCore, cx0, cy0, x1, y1, w * 0.50, 0.14)
                    }
                    let alpha: Double = sinU * (isHero ? 0.94 : 0.74)
                    cellStreaks.append(WarpCellStreak(x0: x0, y0: y0, x1: x1, y1: y1, w: w, color: colColor.alpha(alpha)))
                }
                row += step
            }

            if !cellBack.isEmpty {
                let backA: Double = (f.dark ? 0.22 : 0.34) * wakePresence
                ctx.fill(cellBack, with: .color(warpDeep.alpha(backA).color))
            }
            for s in cellStreaks {
                var sp = Path()
                warpTaperedStreak(&sp, s.x0, s.y0, s.x1, s.y1, s.w, s.w * 0.16)
                ctx.fill(sp, with: .color(s.color.color))
            }
            if !cellCore.isEmpty {
                var cg = ctx
                cg.blendMode = .plusLighter
                cg.fill(cellCore, with: .color(warpCore.alpha(0.86 * wakePresence).color))
            }

            var slipBack = Path()
            var slipBlue = Path()
            var slipCore = Path()
            let slipCount = 44

            for i in 0..<slipCount {
                let h0: Double = closeHash(i, 401, f.seed)
                let h1: Double = closeHash(i, 503, f.seed)
                let h2: Double = closeHash(i, 607, f.seed)

                let start: Double = lerp(0.05, 0.26, h0)
                let dur: Double = lerp(0.34, 0.46, h1)
                let u: Double = phase(f.t, start, start + dur)
                if u <= 0.0 || u >= 1.0 { continue }

                let sinU: Double = sin(Double.pi * u)
                let lane: Double = (h2 - 0.5) * projWidth * 1.18
                let pinchLane: Double = 1.0 - 0.42 * sinU
                let headU: Double = easeInOut(clamp01(u * 1.24))
                let tailU: Double = easeIn(phase(u, 0.18, 1.0))
                let extraLead: Double = lerp(-20.0, 55.0, h1)

                let x1: Double = fromCx + dx * headU + vx * lane * pinchLane + ux * extraLead
                let y1: Double = fromCy + dy * headU + vy * lane * pinchLane + uy * extraLead
                let x0: Double = fromCx + dx * tailU + vx * lane * pinchLane + ux * (extraLead - 48.0)
                let y0: Double = fromCy + dy * tailU + vy * lane * pinchLane + uy * (extraLead - 48.0)

                let w: Double = lerp(0.95, 2.5, h1 * h1) * sinU
                warpTaperedStreak(&slipBack, x0, y0, x1, y1, w * 1.38, w * 0.24)
                warpTaperedStreak(&slipBlue, x0, y0, x1, y1, w * 1.12, w * 0.18)
                let cx0: Double = x0 + (x1 - x0) * 0.36
                let cy0: Double = y0 + (y1 - y0) * 0.36
                warpTaperedStreak(&slipCore, cx0, cy0, x1, y1, w * 0.54, 0.14)
            }

            if !slipBack.isEmpty {
                let backA: Double = (f.dark ? 0.22 : 0.36) * wakePresence
                ctx.fill(slipBack, with: .color(warpDeep.alpha(backA).color))
            }
            if !slipBlue.isEmpty {
                var bg = ctx
                bg.blendMode = f.dark ? .plusLighter : .normal
                let slipHue: RGBA = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.66)
                bg.fill(slipBlue, with: .color(slipHue.alpha(0.86 * wakePresence).color))
            }
            if !slipCore.isEmpty {
                var cg = ctx
                cg.blendMode = .plusLighter
                cg.fill(slipCore, with: .color(warpCore.alpha(0.92 * wakePresence).color))
            }
        }

        // --- Stage 4: Arrival flash, crisp shock ring & anamorphic lens flare ---
        let impactX: Double = toCx
        let impactY: Double = toMinY + toH * 0.34

        let ringT: Double = phase(f.t, 0.48, 0.86)
        if ringT > 0.0 && ringT < 1.0 {
            let ringEase: Double = easeOut(ringT)
            let outerR: Double = lerp(28.0, max(toW, toH) * 0.78, ringEase)
            let innerStop: Double = lerp(0.74, 0.90, ringT)
            let ringFade: Double = sin(Double.pi * ringT) * (1.0 - ringT * 0.40)

            let ringRect = CGRect(x: impactX - outerR, y: impactY - outerR * 0.70, width: outerR * 2.0, height: outerR * 1.40)
            var wg = ctx
            wg.blendMode = f.dark ? .plusLighter : .normal
            let midStop: Double = min(0.96, innerStop + 0.07)
            let ringGrad = Gradient(stops: [
                .init(color: warpBlue.alpha(0.0).color, location: 0.0),
                .init(color: warpBlue.alpha(0.0).color, location: innerStop),
                .init(color: warpCyan.alpha((f.dark ? 0.48 : 0.32) * ringFade).color, location: midStop),
                .init(color: warpCore.alpha((f.dark ? 0.85 : 0.52) * ringFade).color, location: 0.97),
                .init(color: warpBlue.alpha(0.0).color, location: 1.0)
            ])
            wg.fill(Path(ellipseIn: ringRect), with: .radialGradient(ringGrad, center: CGPoint(x: impactX, y: impactY), startRadius: 0, endRadius: outerR))
            if !f.dark {
                ctx.stroke(Path(ellipseIn: ringRect), with: .color(warpCobalt.alpha(0.24 * ringFade).color), lineWidth: 1.6)
            }
        }

        let flashRise: Double = easeOut(phase(f.t, 0.44, 0.53))
        let flashFall: Double = 1.0 - easeOut(phase(f.t, 0.53, 0.80))
        let flash: Double = flashRise * flashFall

        if flash > 0.01 {
            var bloomCtx = ctx
            if !testNoEffects {
                bloomCtx.addFilter(.blur(radius: 14))
            }
            bloomCtx.drawLayer { layer in
                let darkR: Double = lerp(22.0, 98.0, flash)
                let darkRect = CGRect(x: impactX - darkR, y: impactY - darkR * 0.62, width: darkR * 2.0, height: darkR * 1.24)
                layer.fill(Path(ellipseIn: darkRect), with: .color(warpDeep.alpha((f.dark ? 0.28 : 0.46) * flash).color))

                let glowR: Double = lerp(18.0, 90.0, flash)
                let glowRect = CGRect(x: impactX - glowR, y: impactY - glowR * 0.62, width: glowR * 2.0, height: glowR * 1.24)
                layer.fill(Path(ellipseIn: glowRect), with: .color(warpBlue.alpha(0.88 * flash).color))

                let barW: Double = lerp(45.0, 420.0, easeOut(flash))
                let barH: Double = lerp(4.0, 15.0, flash)
                let barRect = CGRect(x: impactX - barW * 0.5, y: impactY - barH * 0.5, width: barW, height: barH)
                layer.fill(Path(ellipseIn: barRect), with: .color(warpCyan.alpha(0.84 * flash).color))
            }

            let flareW: Double = lerp(28.0, 390.0, easeOut(flash))
            let flareH: Double = lerp(2.5, 11.5, flash)
            let vertH: Double = lerp(10.0, 74.0, flash)

            var flareBack = Path()
            warpDiamondFlare(&flareBack, impactX, impactY, flareW * 1.02, flareH * 1.36)
            ctx.fill(flareBack, with: .color(warpDeep.alpha((f.dark ? 0.22 : 0.38) * flash).color))

            var fg = ctx
            fg.blendMode = f.dark ? .plusLighter : .normal
            var horiz = Path()
            warpDiamondFlare(&horiz, impactX, impactY, flareW, flareH)
            fg.fill(horiz, with: .color(warpCyan.alpha(0.92 * flash).color))

            var vert = Path()
            warpDiamondFlare(&vert, impactX, impactY, flareH * 0.85, vertH)
            fg.fill(vert, with: .color(warpCyan.alpha(0.76 * flash).color))

            var cg = ctx
            cg.blendMode = .plusLighter
            var core = Path()
            warpDiamondFlare(&core, impactX, impactY, flareW * 0.60, flareH * 0.52)
            warpDiamondFlare(&core, impactX, impactY, flareH * 0.45, vertH * 0.55)
            cg.fill(core, with: .color(warpCore.alpha(0.98 * flash).color))
        }
    }
}
