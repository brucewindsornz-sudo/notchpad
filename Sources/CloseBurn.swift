import SwiftUI

// Burn closing animation: the pad catches fire at ignition spots along the bottom
// edge and burns upward like paper — toasted scorch, blackened char, incandescent
// ember rim, billowing flames, curling ash shreds, rising embers, and a smoke wisp.

private struct BurnFlame {
    let fx: Double
    let fy: Double
    let h: Double
    let w: Double
    let sway: Double
    let curl: Double
    let activity: Double
}

private func burnFrontY(_ u: Double, _ t: Double, _ pad: CGRect, _ floating: Bool, _ seed: UInt32) -> Double {
    let s1: UInt32 = seed &+ 17
    let s2: UInt32 = seed &+ 53
    let s3: UInt32 = seed &+ 97

    // Two seeded ignition spots along the bottom edge.
    let ig1: Double = 0.16 + closeHash(1, 3, s1) * 0.24
    let ig2: Double = 0.62 + closeHash(2, 5, s1) * 0.24

    let d1: Double = abs(u - ig1)
    let d2: Double = abs(u - ig2)

    let catch1: Double = smoothstep(0.0, 0.18, t)
    let catch2: Double = smoothstep(0.04, 0.24, t)
    let bite1: Double = exp(-d1 * d1 * 11.0) * 0.30 * catch1
    let bite2: Double = exp(-d2 * d2 * 13.0) * 0.24 * catch2

    // Main upward burn sweep after ignition catches.
    let sweepP: Double = phase(t, 0.07, 0.84)
    let sweep: Double = easeInOut(sweepP) * 0.62 + easeIn(sweepP) * 0.56

    // Multi-octave organic paper-burn raggedness.
    let n1: Double = closeNoise(u * 4.8 + 0.7, t * 2.0, s1) - 0.5
    let n2: Double = closeNoise(u * 11.5 + 3.9, t * 3.4, s2) - 0.5
    let n3: Double = closeNoise(u * 25.0 + 8.3, t * 5.2, s3) - 0.5
    let raggedAmp: Double = smoothstep(0.0, 0.12, t)
    let ragged: Double = (n1 * 0.24 + n2 * 0.095 + n3 * 0.04) * raggedAmp

    // Late-stage narrowing so the final charred tongue finishes into f.sink.
    let edgeDist: Double = abs(u - 0.5) * 2.0
    let sideBias: Double = floating
        ? edgeDist * edgeDist * 0.14 * smoothstep(0.22, 0.78, sweepP)
        : edgeDist * edgeDist * 0.28 * smoothstep(0.24, 0.80, sweepP)

    let biteFade: Double = 1.0 - smoothstep(0.55, 0.84, sweepP)
    let totalRise: Double = sweep + (bite1 + bite2) * biteFade + sideBias + ragged

    let startOffset: Double = 22.0 * (1.0 - smoothstep(0.0, 0.14, t))
    return Double(pad.maxY) + startOffset - totalRise * Double(pad.height)
}

struct BurnClose: CloseEffectRenderer {
    let duration: Double = 1.0

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let t: Double = f.t
        if t >= 1.0 { return }
        if t <= 0.0001 {
            f.drawPad(ctx)
            return
        }

        let pad: CGRect = f.pad
        let padMinX: Double = Double(pad.minX)
        let padMaxX: Double = Double(pad.maxX)
        let padMinY: Double = Double(pad.minY)
        let padMaxY: Double = Double(pad.maxY)
        let padMidX: Double = Double(pad.midX)
        let padW: Double = Double(pad.width)
        let padH: Double = Double(pad.height)
        let seed: UInt32 = f.seed

        let samples: Int = 68
        var xs: [Double] = []
        var ys: [Double] = []
        xs.reserveCapacity(samples + 1)
        ys.reserveCapacity(samples + 1)
        var maxFrontY: Double = padMinY - 60.0
        var anyInsidePad: Bool = false

        for i in 0...samples {
            let u: Double = Double(i) / Double(samples)
            let x: Double = padMinX + u * padW
            let y: Double = burnFrontY(u, t, pad, f.floating, seed)
            xs.append(x)
            ys.append(y)
            if y > maxFrontY { maxFrontY = y }
            if y < padMaxY + 2.0 && y > padMinY - 4.0 { anyInsidePad = true }
        }

        let padAlive: Bool = maxFrontY > padMinY - 2.0
        let burnActive: Double = smoothstep(0.0, 0.05, t) * (1.0 - phase(t, 0.78, 0.88))

        // 1. Remaining unburned pad + contour-hugging scorch bands + blackened char rim.
        if padAlive {
            var remainPath = Path()
            remainPath.move(to: CGPoint(x: padMinX - 2.0, y: padMinY - 2.0))
            remainPath.addLine(to: CGPoint(x: padMaxX + 2.0, y: padMinY - 2.0))
            remainPath.addLine(to: CGPoint(x: xs[samples] + 2.0, y: ys[samples]))
            for i in stride(from: samples, through: 0, by: -1) {
                remainPath.addLine(to: CGPoint(x: xs[i], y: ys[i]))
            }
            remainPath.closeSubpath()

            var gPad = ctx
            gPad.clip(to: f.padPath)
            gPad.clip(to: remainPath)
            f.drawPad(gPad)

            // 1b. Two contour-hugging scorch ribbons ahead of the burn line.
            if anyInsidePad {
                let sSc: UInt32 = seed &+ 211
                var outerScorch = Path()
                var innerScorch = Path()
                for i in 0...samples {
                    let n: Double = closeNoise(Double(i) * 0.24, t * 2.2, sSc)
                    let hOut: Double = 20.0 + n * 16.0
                    let hIn: Double = 9.0 + n * 8.0
                    let pOut = CGPoint(x: xs[i], y: ys[i] - hOut)
                    let pIn = CGPoint(x: xs[i], y: ys[i] - hIn)
                    if i == 0 {
                        outerScorch.move(to: pOut)
                        innerScorch.move(to: pIn)
                    } else {
                        outerScorch.addLine(to: pOut)
                        innerScorch.addLine(to: pIn)
                    }
                }
                for i in stride(from: samples, through: 0, by: -1) {
                    let pBot = CGPoint(x: xs[i], y: ys[i] + 2.0)
                    outerScorch.addLine(to: pBot)
                    innerScorch.addLine(to: pBot)
                }
                outerScorch.closeSubpath()
                innerScorch.closeSubpath()

                let outerCol: RGBA = f.dark
                    ? RGBA(0.30, 0.08, 0.01, 0.26)
                    : RGBA(0.58, 0.36, 0.12, 0.28)
                let innerCol: RGBA = f.dark
                    ? RGBA(0.42, 0.11, 0.02, 0.42)
                    : RGBA(0.32, 0.15, 0.04, 0.50)
                gPad.fill(outerScorch, with: .color(outerCol.color))
                gPad.fill(innerScorch, with: .color(innerCol.color))
            }

            // 1c. Blackened char rim right along the burning edge.
            if anyInsidePad {
                var charPath = Path()
                let sChar: UInt32 = seed &+ 307
                let sDrop: UInt32 = seed &+ 313
                for i in 0...samples {
                    let thick: Double = 5.0 + closeNoise(Double(i) * 0.42, t * 2.8, sChar) * 8.0
                    let pt = CGPoint(x: xs[i], y: ys[i] - thick)
                    if i == 0 { charPath.move(to: pt) } else { charPath.addLine(to: pt) }
                }
                for i in stride(from: samples, through: 0, by: -1) {
                    let droop: Double = closeNoise(Double(i) * 0.55, t * 3.8, sDrop) * 4.0
                    charPath.addLine(to: CGPoint(x: xs[i], y: ys[i] + droop))
                }
                charPath.closeSubpath()

                var gChar = ctx
                gChar.clip(to: f.padPath)
                gChar.fill(charPath, with: .color(RGBA(0.05, 0.035, 0.03, 0.96).color))
            }
        }

        // 2. Delicate curling smoke wisps (single blurred layer).
        let smokeFade: Double = phase(t, 0.05, 0.18) * (1.0 - easeIn(phase(t, 0.80, 1.0)))
        if smokeFade > 0.01 {
            var gSmoke = ctx
            if !testNoEffects { gSmoke.addFilter(.blur(radius: 9.0)) }
            gSmoke.drawLayer { layer in
                let sSmoke: UInt32 = seed &+ 409
                let ribbonCount: Int = 9
                for i in 0..<ribbonCount {
                    let u: Double = 0.14 + closeHash(i, 1, sSmoke) * 0.72
                    let startT: Double = 0.04 + closeHash(i, 2, sSmoke) * 0.56
                    let lifeLen: Double = 0.34 + closeHash(i, 3, sSmoke) * 0.24
                    let life: Double = phase(t, startT, startT + lifeLen)
                    if life <= 0.0 || life >= 1.0 { continue }

                    let spawnY: Double = burnFrontY(u, startT, pad, f.floating, seed)
                    if spawnY > padMaxY + 2.0 || spawnY < padMinY - 8.0 { continue }

                    let baseX: Double = padMinX + u * padW
                    let rise: Double = easeOut(life) * (65.0 + closeHash(i, 4, sSmoke) * 70.0)
                    let drift: Double = (closeHash(i, 5, sSmoke) - 0.5) * 40.0 * life
                    let phaseOff: Double = closeHash(i, 6, sSmoke) * 6.28

                    var rp = Path()
                    let segs: Int = 6
                    let ribbonLen: Double = 36.0 + life * 44.0
                    for k in 0...segs {
                        let frac: Double = Double(k) / Double(segs)
                        let ry: Double = spawnY - rise * 0.55 - frac * ribbonLen
                        let wave: Double = sin(life * 5.0 + frac * 3.4 + phaseOff) * (8.0 + frac * 12.0)
                        let rx: Double = baseX + drift * (0.4 + frac * 0.6) + wave
                        let pt = CGPoint(x: rx, y: ry)
                        if k == 0 { rp.move(to: pt) } else { rp.addLine(to: pt) }
                    }

                    let alpha: Double = sin(Double.pi * life) * 0.15 * smokeFade
                    let grey: Double = f.dark ? 0.34 : 0.24
                    let lw: CGFloat = CGFloat(lerp(8.0, 20.0, life))
                    layer.stroke(
                        rp,
                        with: .color(RGBA(grey, grey * 0.96, grey * 0.93, alpha).color),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
                    )
                }

                // Final graceful smoke wisp curling from the last burn point.
                let wispLife: Double = phase(t, 0.68, 1.0)
                if wispLife > 0.0 && wispLife < 1.0 {
                    let wispAlpha: Double = sin(Double.pi * wispLife) * 0.20
                    let ox: Double = f.floating ? padMidX : Double(f.sink.midX)
                    let oy: Double = f.floating ? padMinY + padH * 0.22 : Double(f.sink.maxY) + 28.0
                    let seedMod: Double = Double(seed % 5)
                    var wp = Path()
                    for k in 0...7 {
                        let frac: Double = Double(k) / 7.0
                        let wy: Double = oy - frac * (55.0 + wispLife * 35.0) - wispLife * 18.0
                        let wx: Double = ox + sin(wispLife * 6.0 + frac * 3.8 + seedMod) * (5.0 + frac * 14.0)
                        let pt = CGPoint(x: wx, y: wy)
                        if k == 0 { wp.move(to: pt) } else { wp.addLine(to: pt) }
                    }
                    let lw: CGFloat = CGFloat(lerp(6.0, 15.0, wispLife))
                    layer.stroke(
                        wp,
                        with: .color(RGBA(0.30, 0.28, 0.27, wispAlpha).color),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }

        // 3. Incandescent glowing edge & organic billowing flames.
        if padAlive && anyInsidePad && burnActive > 0.01 {
            var glowLine = Path()
            var penDown: Bool = false
            for i in 0...samples {
                let y: Double = ys[i]
                if y <= padMaxY + 1.0 && y >= padMinY - 4.0 {
                    let cy: Double = max(padMinY, min(padMaxY, y))
                    let pt = CGPoint(x: xs[i], y: cy)
                    if !penDown {
                        glowLine.move(to: pt)
                        penDown = true
                    } else {
                        glowLine.addLine(to: pt)
                    }
                } else {
                    penDown = false
                }
            }

            let sFlame: UInt32 = seed &+ 521
            let sSway: UInt32 = seed &+ 547
            let flameCount: Int = 12
            var flames: [BurnFlame] = []
            flames.reserveCapacity(flameCount)

            for i in 0..<flameCount {
                let jitter: Double = (closeHash(i, 1, sFlame) - 0.5) * 0.75
                let u: Double = 0.06 + ((Double(i) + 0.5 + jitter) / Double(flameCount)) * 0.88
                let idx: Int = max(0, min(samples, Int((u * Double(samples)).rounded())))
                let fy: Double = ys[idx]
                if fy > padMaxY + 0.5 || fy < padMinY - 2.0 { continue }

                let activity: Double = closeNoise(Double(i) * 1.63, t * 11.0, sFlame)
                if activity < 0.22 { continue }

                let sizeBias: Double = 0.65 + closeHash(i, 2, sFlame) * 0.85
                let edgeFade: Double = smoothstep(0.02, 0.12, u) * smoothstep(0.98, 0.88, u)
                let h: Double = (16.0 + activity * 36.0) * sizeBias * burnActive * (0.5 + 0.5 * edgeFade)
                let w: Double = (10.0 + closeHash(i, 3, sFlame) * 12.0) * (0.65 + 0.45 * activity)
                let sway: Double = (closeNoise(Double(i) * 2.3, t * 9.5, sSway) - 0.5) * 20.0
                let curl: Double = (closeNoise(Double(i) * 3.1, t * 12.0, sSway) - 0.5) * 14.0
                flames.append(BurnFlame(fx: xs[idx], fy: fy, h: h, w: w, sway: sway, curl: curl, activity: activity))
            }

            // 3a. Soft fire bloom + outer flame glow in ONE blurred layer.
            var gFireGlow = ctx
            if !testNoEffects { gFireGlow.addFilter(.blur(radius: 8.0)) }
            gFireGlow.drawLayer { layer in
                layer.stroke(
                    glowLine,
                    with: .color(RGBA(1.0, 0.28, 0.02, 0.92 * burnActive).color),
                    style: StrokeStyle(lineWidth: 12.0, lineCap: .round, lineJoin: .round)
                )

                for fl in flames {
                    var fp = Path()
                    fp.move(to: CGPoint(x: fl.fx - fl.w * 0.62, y: fl.fy + 3.0))
                    fp.addCurve(
                        to: CGPoint(x: fl.fx + fl.sway, y: fl.fy - fl.h * 1.08),
                        control1: CGPoint(x: fl.fx - fl.w * 0.90, y: fl.fy - fl.h * 0.35),
                        control2: CGPoint(x: fl.fx - fl.w * 0.25 + fl.curl, y: fl.fy - fl.h * 0.78)
                    )
                    fp.addCurve(
                        to: CGPoint(x: fl.fx + fl.w * 0.62, y: fl.fy + 3.0),
                        control1: CGPoint(x: fl.fx + fl.w * 0.30 + fl.curl, y: fl.fy - fl.h * 0.75),
                        control2: CGPoint(x: fl.fx + fl.w * 0.90, y: fl.fy - fl.h * 0.35)
                    )
                    fp.closeSubpath()
                    layer.fill(fp, with: .color(RGBA(1.0, 0.34, 0.03, 0.72 * burnActive).color))
                }
            }

            // 3b. Layered organic flames (rich amber-orange body + white-yellow core).
            for fl in flames {
                var fp = Path()
                fp.move(to: CGPoint(x: fl.fx - fl.w * 0.54, y: fl.fy + 2.0))
                fp.addCurve(
                    to: CGPoint(x: fl.fx + fl.sway, y: fl.fy - fl.h),
                    control1: CGPoint(x: fl.fx - fl.w * 0.78, y: fl.fy - fl.h * 0.34),
                    control2: CGPoint(x: fl.fx - fl.w * 0.18 + fl.curl, y: fl.fy - fl.h * 0.72)
                )
                fp.addCurve(
                    to: CGPoint(x: fl.fx + fl.w * 0.54, y: fl.fy + 2.0),
                    control1: CGPoint(x: fl.fx + fl.w * 0.22 + fl.curl, y: fl.fy - fl.h * 0.70),
                    control2: CGPoint(x: fl.fx + fl.w * 0.78, y: fl.fy - fl.h * 0.34)
                )
                fp.closeSubpath()

                let flameGrad = Gradient(stops: [
                    .init(color: RGBA(1.0, 0.88, 0.36, 0.92 * burnActive).color, location: 0.0),
                    .init(color: RGBA(1.0, 0.44, 0.05, 0.80 * burnActive).color, location: 0.55),
                    .init(color: RGBA(0.88, 0.15, 0.01, 0.0).color, location: 1.0),
                ])
                ctx.fill(
                    fp,
                    with: .linearGradient(
                        flameGrad,
                        startPoint: CGPoint(x: fl.fx, y: fl.fy + 2.0),
                        endPoint: CGPoint(x: fl.fx + fl.sway, y: fl.fy - fl.h)
                    )
                )

                if fl.activity > 0.38 {
                    let ch: Double = fl.h * 0.54
                    let cw: Double = fl.w * 0.44
                    var cp = Path()
                    cp.move(to: CGPoint(x: fl.fx - cw * 0.5, y: fl.fy + 1.0))
                    cp.addQuadCurve(
                        to: CGPoint(x: fl.fx + fl.sway * 0.45, y: fl.fy - ch),
                        control: CGPoint(x: fl.fx - cw * 0.65, y: fl.fy - ch * 0.48)
                    )
                    cp.addQuadCurve(
                        to: CGPoint(x: fl.fx + cw * 0.5, y: fl.fy + 1.0),
                        control: CGPoint(x: fl.fx + cw * 0.65 + fl.sway * 0.2, y: fl.fy - ch * 0.48)
                    )
                    cp.closeSubpath()
                    ctx.fill(cp, with: .color(RGBA(1.0, 0.97, 0.76, 0.86 * burnActive).color))
                }
            }

            // 3c. Crisp molten ember line right on the char boundary.
            var gEmberLine = ctx
            gEmberLine.clip(to: f.padPath)
            gEmberLine.stroke(
                glowLine,
                with: .color(RGBA(1.0, 0.46, 0.05, 0.96 * burnActive).color),
                style: StrokeStyle(lineWidth: 4.0, lineCap: .round, lineJoin: .round)
            )
            var gHotLine = gEmberLine
            gHotLine.blendMode = .plusLighter
            gHotLine.stroke(
                glowLine,
                with: .color(RGBA(1.0, 0.94, 0.58, 0.88 * burnActive).color),
                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)
            )
        }

        // 4. Charred ash flakes & curling shreds peeling off behind the burn front.
        let sAsh: UInt32 = seed &+ 619
        let ashCount: Int = 46
        for i in 0..<ashCount {
            let u: Double = 0.04 + closeHash(i, 1, sAsh) * 0.92
            let v: Double = 0.05 + closeHash(i, 2, sAsh) * 0.90
            let cellX: Double = padMinX + u * padW
            let cellY: Double = padMinY + v * padH

            let igniteT: Double = lerp(0.05, 0.76, 1.0 - v) + (closeHash(i, 3, sAsh) - 0.5) * 0.08
            let life: Double = phase(t, igniteT, igniteT + 0.28)
            if life <= 0.0 || life >= 1.0 { continue }

            let curFront: Double = burnFrontY(u, t, pad, f.floating, seed)
            if curFront > cellY + 3.0 { continue }

            let col: Int = max(0, min(f.cells.cols - 1, Int((u * Double(f.cells.cols)).rounded(.down))))
            let row: Int = max(0, min(f.cells.rows - 1, Int((v * Double(f.cells.rows)).rounded(.down))))
            let cellColor: RGBA = f.cells.color(col, row)
            if cellColor.a <= 0.05 { continue }

            let ashBase: RGBA = cellColor.mix(RGBA(0.06, 0.045, 0.04, 1.0), 0.85)
            let flutter: Double = sin(life * 8.5 + Double(i) * 2.1) * 11.0 * life
            let driftX: Double = (closeHash(i, 4, sAsh) - 0.5) * 34.0 * life + flutter
            let liftArc: Double = sin(Double.pi * min(1.0, life * 1.3))
            let driftY: Double = -16.0 * liftArc + 28.0 * life * life
            let px: Double = cellX + driftX
            let py: Double = cellY + driftY

            let big: Double = closeHash(i, 8, sAsh) > 0.78 ? 1.55 : 1.0
            let size: Double = (3.4 + closeHash(i, 5, sAsh) * 5.2) * big * (1.0 - 0.40 * life)
            let spinDir: Double = closeHash(i, 7, sAsh) > 0.5 ? 2.8 : -2.8
            let rot: Double = (closeHash(i, 6, sAsh) - 0.5) * 3.0 + life * spinDir
            let alpha: Double = (1.0 - easeIn(life)) * 0.92

            var gFlake = ctx
            gFlake.translateBy(x: CGFloat(px), y: CGFloat(py))
            gFlake.rotate(by: .radians(rot))
            var fp = Path()
            fp.move(to: CGPoint(x: -size * 0.65, y: -size * 0.35))
            fp.addLine(to: CGPoint(x: size * 0.55, y: -size * 0.45))
            fp.addLine(to: CGPoint(x: size * 0.68, y: size * 0.32))
            fp.addLine(to: CGPoint(x: -size * 0.42, y: size * 0.48))
            fp.closeSubpath()
            gFlake.fill(fp, with: .color(ashBase.alpha(alpha).color))

            if life < 0.42 {
                let emberAlpha: Double = (1.0 - life / 0.42) * 0.90
                gFlake.stroke(fp, with: .color(RGBA(1.0, 0.44, 0.05, emberAlpha).color), lineWidth: 1.1)
            }
        }

        // 5. Brief warm afterglow at the final burn zone + rising glowing embers.
        let lipGlow: Double = sin(Double.pi * phase(t, 0.72, 0.88))
        if lipGlow > 0.01 {
            let gx: Double = f.floating ? padMidX : Double(f.sink.midX)
            let gy: Double = f.floating ? padMinY + padH * 0.14 : Double(f.sink.maxY) - 2.0
            let gw: Double = f.floating ? 120.0 : Double(f.sink.width) * 0.75
            let gh: Double = 22.0
            var gLip = ctx
            if !testNoEffects { gLip.addFilter(.blur(radius: 8.0)) }
            gLip.fill(
                Path(ellipseIn: CGRect(x: gx - gw * 0.5, y: gy - gh * 0.5, width: gw, height: gh)),
                with: .color(RGBA(1.0, 0.36, 0.04, 0.42 * lipGlow).color)
            )
        }

        let sEmb: UInt32 = seed &+ 733
        let emberCount: Int = 115
        var hotEmberPath = Path()
        var warmEmberPath = Path()
        var coolEmberPath = Path()

        for i in 0..<emberCount {
            let isLate: Bool = i >= emberCount - 25
            let spread: Double = (closeHash(i, 1, sEmb) + closeHash(i, 11, sEmb)) * 0.5
            let u: Double = isLate
                ? 0.22 + spread * 0.56
                : 0.05 + closeHash(i, 1, sEmb) * 0.90
            let spawnT: Double = isLate
                ? 0.68 + closeHash(i, 2, sEmb) * 0.14
                : 0.02 + closeHash(i, 2, sEmb) * 0.72
            let lifeLen: Double = isLate
                ? 0.16 + closeHash(i, 3, sEmb) * 0.16
                : 0.22 + closeHash(i, 3, sEmb) * 0.24
            let life: Double = phase(t, spawnT, spawnT + lifeLen)
            if life <= 0.0 || life >= 1.0 { continue }

            var startY: Double = burnFrontY(u, spawnT, pad, f.floating, seed)
            if isLate {
                startY = f.floating
                    ? padMinY + padH * (0.14 + closeHash(i, 9, sEmb) * 0.22)
                    : Double(f.sink.maxY) + 6.0 + closeHash(i, 9, sEmb) * 42.0
            } else if startY > padMaxY + 2.0 || startY < padMinY - 8.0 {
                continue
            }

            let startX: Double = padMinX + u * padW
            let speedY: Double = isLate
                ? 24.0 + closeHash(i, 4, sEmb) * 52.0
                : 60.0 + closeHash(i, 4, sEmb) * 110.0
            let swayAmp: Double = 8.0 + closeHash(i, 5, sEmb) * 18.0
            let swayFreq: Double = 4.0 + closeHash(i, 6, sEmb) * 5.0
            let windX: Double = (closeHash(i, 7, sEmb) - 0.5) * (isLate ? 64.0 : 44.0)

            let vertDisp: Double = (isLate && !f.floating)
                ? (closeHash(i, 10, sEmb) - 0.35) * 46.0 * easeOut(life)
                : -speedY * easeOut(life)

            let ex: Double = startX + windX * easeOut(life) + sin(life * swayFreq + Double(i) * 1.9) * swayAmp * life
            let ey: Double = startY + vertDisp
            if ey < 2.0 { continue }

            let baseR: Double = 1.1 + closeHash(i, 8, sEmb) * 2.4
            let r: Double = baseR * (1.0 - 0.50 * life)
            let streakH: Double = r * (1.5 + (speedY / 115.0) * 1.1 * (1.0 - life))
            let emberRect = CGRect(x: ex - r * 0.75, y: ey - streakH, width: r * 1.5, height: streakH * 2.0)

            let pulse: Double = 0.65 + 0.35 * sin(t * 38.0 + Double(i) * 3.1)
            let fade: Double = (1.0 - easeIn(life)) * pulse
            if fade < 0.08 { continue }

            if life < 0.32 {
                hotEmberPath.addEllipse(in: emberRect)
            } else if life < 0.68 {
                warmEmberPath.addEllipse(in: emberRect)
            } else {
                coolEmberPath.addEllipse(in: emberRect)
            }
        }

        // Ember glow halo.
        var gEmbGlow = ctx
        if !testNoEffects { gEmbGlow.addFilter(.blur(radius: 3.5)) }
        gEmbGlow.fill(hotEmberPath, with: .color(RGBA(1.0, 0.55, 0.08, 0.88).color))
        gEmbGlow.fill(warmEmberPath, with: .color(RGBA(1.0, 0.28, 0.02, 0.68).color))

        // Crisp ember cores.
        ctx.fill(coolEmberPath, with: .color(RGBA(0.82, 0.20, 0.02, 0.80).color))
        ctx.fill(warmEmberPath, with: .color(RGBA(1.0, 0.52, 0.08, 0.96).color))
        ctx.fill(hotEmberPath, with: .color(RGBA(1.0, 0.96, 0.74, 1.0).color))
    }
}
