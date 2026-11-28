import SwiftUI

// Melt ("Liquid metal") closing animation: the pad liquefies into mirror-bright
// mercury with soft 3D chrome reflections and specular glints, flowing upward in
// curved meniscus tendrils into the notch (docked) or dripping and coalescing
// seamlessly into a trembling mercury bead (floating).

private func meltSign(_ x: Double) -> Double {
    if x > 0.0 { return 1.0 }
    if x < 0.0 { return -1.0 }
    return 0.0
}

private func meltDrawBead(
    _ ctx: GraphicsContext,
    cx: Double, cy: Double, rx: Double, ry: Double, stretchY: Double,
    chromeBright: RGBA, chromeSilver: RGBA, chromeDark: RGBA, alpha: Double
) {
    if rx < 0.6 || ry < 0.6 || alpha <= 0.02 { return }

    var p = Path()
    if abs(stretchY) < 0.15 {
        p.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2.0, height: ry * 2.0))
    } else {
        let tipY: Double = cy + stretchY * ry * 2.2
        let baseY: Double = cy - meltSign(stretchY) * ry * 0.85
        p.move(to: CGPoint(x: cx, y: tipY))
        p.addCurve(
            to: CGPoint(x: cx + rx, y: cy),
            control1: CGPoint(x: cx + rx * 0.45, y: lerp(tipY, cy, 0.55)),
            control2: CGPoint(x: cx + rx, y: lerp(cy, tipY, 0.25))
        )
        p.addCurve(
            to: CGPoint(x: cx, y: baseY),
            control1: CGPoint(x: cx + rx, y: lerp(cy, baseY, 0.62)),
            control2: CGPoint(x: cx + rx * 0.55, y: baseY)
        )
        p.addCurve(
            to: CGPoint(x: cx - rx, y: cy),
            control1: CGPoint(x: cx - rx * 0.55, y: baseY),
            control2: CGPoint(x: cx - rx, y: lerp(cy, baseY, 0.62))
        )
        p.addCurve(
            to: CGPoint(x: cx, y: tipY),
            control1: CGPoint(x: cx - rx, y: lerp(cy, tipY, 0.25)),
            control2: CGPoint(x: cx - rx * 0.45, y: lerp(tipY, cy, 0.55))
        )
        p.closeSubpath()
    }

    let maxR: Double = max(rx, ry) * 1.45
    let hiPt = CGPoint(x: cx - rx * 0.30, y: cy - ry * 0.32)
    let grad = Gradient(stops: [
        .init(color: RGBA.white.alpha(alpha).color, location: 0.0),
        .init(color: chromeBright.alpha(alpha).color, location: 0.22),
        .init(color: chromeSilver.alpha(alpha).color, location: 0.48),
        .init(color: chromeDark.alpha(alpha).color, location: 0.78),
        .init(color: chromeSilver.alpha(alpha * 0.92).color, location: 1.0),
    ])
    ctx.fill(p, with: .radialGradient(grad, center: hiPt, startRadius: 0.0, endRadius: CGFloat(maxR)))
    ctx.stroke(p, with: .color(chromeDark.alpha(0.55 * alpha).color), lineWidth: 0.9)

    let sr: Double = max(0.9, rx * 0.28)
    let specRect = CGRect(x: cx - rx * 0.36 - sr * 0.6, y: cy - ry * 0.36 - sr * 0.45, width: sr * 1.3, height: sr * 0.9)
    ctx.fill(Path(ellipseIn: specRect), with: .color(RGBA.white.alpha(0.95 * alpha).color))
}

private func meltDockedDripY(_ u: Double, _ t: Double, _ pad: CGRect, _ sink: CGRect, _ seed: UInt32) -> Double {
    let s1: UInt32 = seed &+ 31
    let s2: UInt32 = seed &+ 89

    let sag: Double = sin(Double.pi * phase(t, 0.0, 0.26)) * 22.0
    let drain: Double = easeInOut(phase(t, 0.14, 0.84))
    let finalPull: Double = easeIn(phase(t, 0.70, 0.89))

    let cDist: Double = abs(u - 0.5) * 2.0
    let funnel: Double = pow(cDist, 1.8) * 0.46 * smoothstep(0.08, 0.60, t)
    let edgeDrain: Double = clamp01(drain * 1.18 + funnel)

    let lobePhase: Double = smoothstep(0.02, 0.18, t) * (1.0 - smoothstep(0.64, 0.88, t))
    let w1Base: Double = 0.5 + 0.5 * sin(u * Double.pi * 5.0 + closeHash(1, 2, s1) * 3.0)
    let w2Base: Double = 0.5 + 0.5 * sin(u * Double.pi * 9.0 + closeHash(3, 4, s2) * 4.0 + t * 2.0)
    let w1: Double = pow(w1Base, 2.4)
    let w2: Double = pow(w2Base, 2.8)
    let n: Double = closeNoise(u * 4.2 + 0.4, t * 2.2, s1)
    let dripExtra: Double = (w1 * 42.0 + w2 * 20.0 + n * 14.0) * lobePhase * (1.0 - cDist * 0.52)

    let baseBottom: Double = lerp(Double(pad.maxY) + sag, Double(sink.maxY) + 4.0, edgeDrain)
    let y: Double = baseBottom + dripExtra * (1.0 - finalPull)
    return lerp(y, Double(sink.minY) - 2.0, finalPull)
}

private func meltDrawReflections(
    _ ctx: GraphicsContext,
    bodyPath: Path, bLeft: Double, bRight: Double, bTop: Double, bBot: Double,
    t: Double, chromeDark: RGBA, alpha: Double
) {
    let bw: Double = max(4.0, bRight - bLeft)
    let bh: Double = max(4.0, bBot - bTop)
    var gRef = ctx
    gRef.clip(to: bodyPath)
    gRef.opacity = gRef.opacity * alpha
    if !testNoEffects { gRef.addFilter(.blur(radius: 9.0)) }
    gRef.drawLayer { layer in
        // Upper sky-bright specular caustic band.
        let y1: Double = bTop + bh * (0.16 + sin(t * 6.0) * 0.04)
        let r1 = CGRect(x: bLeft + bw * 0.08, y: y1 - bh * 0.08, width: bw * 0.72, height: bh * 0.18)
        layer.fill(Path(ellipseIn: r1), with: .color(RGBA.white.alpha(0.65).color))

        // Undulating dark horizon trough.
        let y2: Double = bTop + bh * (0.48 + sin(t * 7.2 + 1.1) * 0.05)
        var p2 = Path()
        for i in 0...16 {
            let u: Double = Double(i) / 16.0
            let x: Double = bLeft - 10.0 + u * (bw + 20.0)
            let y: Double = y2 + sin(u * Double.pi * 2.5 + t * 6.5) * (bh * 0.07)
            let pt = CGPoint(x: x, y: y)
            if i == 0 { p2.move(to: pt) } else { p2.addLine(to: pt) }
        }
        let lw: CGFloat = CGFloat(max(6.0, bh * 0.14))
        layer.stroke(
            p2,
            with: .color(chromeDark.alpha(0.72).color),
            style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)
        )

        // Lower bright ground-bounce specular curve.
        let y3: Double = bTop + bh * (0.76 + cos(t * 6.8) * 0.04)
        let r3 = CGRect(x: bLeft + bw * 0.18, y: y3 - bh * 0.07, width: bw * 0.64, height: bh * 0.14)
        layer.fill(Path(ellipseIn: r3), with: .color(RGBA.white.alpha(0.55).color))
    }
}

private func meltDrawStarGlint(
    _ ctx: GraphicsContext, gx: Double, gy: Double, pulse: Double, maxR: Double, chromeBright: RGBA
) {
    if pulse <= 0.01 { return }
    let starR: Double = (8.0 + pulse * maxR) * pulse
    let starW: Double = 1.7 * pulse
    var sp = Path()
    sp.move(to: CGPoint(x: gx, y: gy - starR * 0.85))
    sp.addLine(to: CGPoint(x: gx + starW, y: gy - starW))
    sp.addLine(to: CGPoint(x: gx + starR, y: gy))
    sp.addLine(to: CGPoint(x: gx + starW, y: gy + starW))
    sp.addLine(to: CGPoint(x: gx, y: gy + starR * 0.85))
    sp.addLine(to: CGPoint(x: gx - starW, y: gy + starW))
    sp.addLine(to: CGPoint(x: gx - starR, y: gy))
    sp.addLine(to: CGPoint(x: gx - starW, y: gy - starW))
    sp.closeSubpath()

    var gBloom = ctx
    if !testNoEffects { gBloom.addFilter(.blur(radius: 4.0)) }
    gBloom.fill(sp, with: .color(chromeBright.alpha(0.75 * pulse).color))
    ctx.fill(sp, with: .color(RGBA.white.alpha(0.95 * pulse).color))
}

struct MeltClose: CloseEffectRenderer {
    let duration: Double = 1.0

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let t: Double = f.t
        if t >= 1.0 { return }
        if t <= 0.0001 {
            f.drawPad(ctx)
            return
        }

        let pad: CGRect = f.pad
        let sink: CGRect = f.sink
        let padMinX: Double = Double(pad.minX)
        let padMaxX: Double = Double(pad.maxX)
        let padMinY: Double = Double(pad.minY)
        let padMaxY: Double = Double(pad.maxY)
        let padMidX: Double = Double(pad.midX)
        let padMidY: Double = Double(pad.midY)
        let padW: Double = Double(pad.width)
        let padH: Double = Double(pad.height)
        let sinkMinX: Double = Double(sink.minX)
        let sinkMaxX: Double = Double(sink.maxX)
        let sinkMinY: Double = Double(sink.minY)
        let sinkMidX: Double = Double(sink.midX)
        let sinkW: Double = Double(sink.width)
        let seed: UInt32 = f.seed

        // High-contrast mirror mercury palette with a subtle touch of theme accent.
        let chromeBright: RGBA = RGBA(0.95, 0.97, 1.0, 1.0).mix(f.accent, 0.08)
        let chromeSilver: RGBA = RGBA(0.75, 0.79, 0.86, 1.0).mix(f.accent, 0.12)
        let chromeMid: RGBA = RGBA(0.44, 0.48, 0.55, 1.0).mix(f.accent, 0.10)
        let chromeDark: RGBA = RGBA(0.08, 0.10, 0.14, 1.0).mix(f.bg, 0.14)

        let metalBlend: Double = smoothstep(0.06, 0.44, t)
        let padReveal: Double = 1.0 - smoothstep(0.14, 0.46, t)

        if !f.floating {
            // DOCKED MODE: liquefies and drains upward in curved chrome tendrils into f.sink.
            let bodyAlive: Bool = t < 0.89
            let narrow: Double = easeInOut(phase(t, 0.16, 0.84))
            let finalPinch: Double = easeIn(phase(t, 0.72, 0.88))
            let leftX: Double = lerp(padMinX, sinkMinX + 10.0, narrow)
            let rightX: Double = lerp(padMaxX, sinkMaxX - 10.0, narrow)
            let curL: Double = lerp(leftX, sinkMidX - 8.0, finalPinch)
            let curR: Double = lerp(rightX, sinkMidX + 8.0, finalPinch)
            let curW: Double = max(2.0, curR - curL)

            if bodyAlive {
                let samples: Int = 56
                let topY: Double = padMinY
                let topInset: Double = lerp(12.0, 2.0, narrow)
                let bodyLeftX: Double = curL + topInset
                let bodyRightX: Double = curR - topInset
                let innerW: Double = max(2.0, bodyRightX - bodyLeftX)
                let cornerR: Double = lerp(22.0, 6.0, narrow)

                var bodyPath = Path()
                bodyPath.move(to: CGPoint(x: curL, y: topY))
                bodyPath.addLine(to: CGPoint(x: curR, y: topY))
                bodyPath.addQuadCurve(
                    to: CGPoint(x: bodyRightX, y: topY + topInset),
                    control: CGPoint(x: bodyRightX, y: topY)
                )

                let yRight: Double = meltDockedDripY(1.0, t, pad, sink, seed)
                let meniscusPull: Double = innerW * 0.12 * smoothstep(0.20, 0.75, t)
                bodyPath.addQuadCurve(
                    to: CGPoint(x: bodyRightX - meniscusPull, y: max(topY + topInset, yRight - cornerR * 0.6)),
                    control: CGPoint(x: bodyRightX, y: lerp(topY + topInset, yRight, 0.45))
                )

                for i in stride(from: samples, through: 0, by: -1) {
                    let u: Double = Double(i) / Double(samples)
                    let x: Double = lerp(bodyLeftX + meniscusPull, bodyRightX - meniscusPull, u)
                    var y: Double = meltDockedDripY(u, t, pad, sink, seed)
                    let edgeU: Double = min(u, 1.0 - u)
                    if edgeU < 0.06 {
                        let cf: Double = 1.0 - edgeU / 0.06
                        y -= cf * cf * cornerR * (1.0 - narrow * 0.65)
                    }
                    bodyPath.addLine(to: CGPoint(x: x, y: max(topY + 1.0, y)))
                }

                let yLeft: Double = meltDockedDripY(0.0, t, pad, sink, seed)
                bodyPath.addQuadCurve(
                    to: CGPoint(x: bodyLeftX, y: topY + topInset),
                    control: CGPoint(x: bodyLeftX, y: lerp(topY + topInset, yLeft, 0.45))
                )
                bodyPath.addQuadCurve(
                    to: CGPoint(x: curL, y: topY),
                    control: CGPoint(x: bodyLeftX, y: topY)
                )
                bodyPath.closeSubpath()

                // 1. Melting pad texture drawn inside ONE opacity layer so strips have zero seams.
                if padReveal > 0.01 {
                    var gPad = ctx
                    gPad.clip(to: bodyPath)
                    gPad.opacity = gPad.opacity * padReveal
                    if t < 0.06 {
                        f.drawPad(gPad, in: pad, opacity: 1.0)
                    } else {
                        gPad.drawLayer { layer in
                            let strips: Int = 24
                            let spanL: Double = bodyLeftX
                            let spanW: Double = innerW
                            for i in 0..<strips {
                                let u: Double = (Double(i) + 0.5) / Double(strips)
                                let targetY: Double = meltDockedDripY(u, t, pad, sink, seed)
                                let scaleY: Double = max(0.08, (targetY - padMinY) / padH)
                                let dstX: Double = spanL + (Double(i) / Double(strips)) * spanW
                                let dstW: Double = spanW / Double(strips) + 0.6
                                var gStrip = layer
                                let clipRect = CGRect(x: dstX - 0.2, y: padMinY, width: dstW, height: max(4.0, targetY - padMinY + 4.0))
                                gStrip.clip(to: Path(clipRect))
                                let mappedRect = CGRect(x: spanL, y: padMinY, width: spanW, height: padH * scaleY)
                                f.drawPad(gStrip, in: mappedRect, opacity: 1.0)
                            }
                        }
                    }
                }

                // 2. Liquid-chrome metallic shading + soft blurred 3D reflections.
                if metalBlend > 0.01 {
                    let bb: CGRect = bodyPath.boundingRect
                    let bTop: Double = Double(bb.minY)
                    let bBot: Double = max(bTop + 8.0, Double(bb.maxY))
                    let horizonShift: Double = sin(t * 7.5) * 0.05
                    let chromeAlpha: Double = metalBlend * (1.0 - phase(t, 0.82, 0.89))

                    var gChrome = ctx
                    gChrome.opacity = gChrome.opacity * chromeAlpha
                    let chromeGrad = Gradient(stops: [
                        .init(color: chromeBright.color, location: 0.0),
                        .init(color: chromeSilver.color, location: 0.22),
                        .init(color: chromeDark.color, location: clamp01(0.46 + horizonShift)),
                        .init(color: chromeMid.color, location: clamp01(0.56 + horizonShift)),
                        .init(color: chromeBright.color, location: 0.78),
                        .init(color: chromeDark.mix(chromeMid, 0.35).color, location: 1.0),
                    ])
                    gChrome.fill(
                        bodyPath,
                        with: .linearGradient(
                            chromeGrad,
                            startPoint: CGPoint(x: padMidX - curW * 0.14, y: bTop),
                            endPoint: CGPoint(x: padMidX + curW * 0.14, y: bBot)
                        )
                    )

                    meltDrawReflections(
                        ctx, bodyPath: bodyPath,
                        bLeft: Double(bb.minX), bRight: Double(bb.maxX), bTop: bTop, bBot: bBot,
                        t: t, chromeDark: chromeDark, alpha: chromeAlpha
                    )

                    var gRimHi = ctx
                    gRimHi.clip(to: bodyPath)
                    var hiLine = Path()
                    for i in 3...(samples - 3) {
                        let u: Double = Double(i) / Double(samples)
                        let x: Double = lerp(bodyLeftX + meniscusPull, bodyRightX - meniscusPull, u)
                        let y: Double = meltDockedDripY(u, t, pad, sink, seed) - 5.0
                        let pt = CGPoint(x: x, y: max(topY + 2.0, y))
                        if i == 3 { hiLine.move(to: pt) } else { hiLine.addLine(to: pt) }
                    }
                    gRimHi.stroke(
                        hiLine,
                        with: .color(RGBA.white.alpha(0.75 * chromeAlpha * (1.0 - finalPinch)).color),
                        style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round)
                    )

                    gChrome.stroke(bodyPath, with: .color(chromeDark.alpha(0.65).color), lineWidth: 1.3)
                }

                // 2b. Early liquefaction chrome sheen wave sweeping upward.
                let sheenP: Double = phase(t, 0.0, 0.30)
                if sheenP > 0.0 && sheenP < 1.0 {
                    var gSheen = ctx
                    gSheen.clip(to: bodyPath)
                    let sheenY: Double = lerp(padMaxY + 30.0, padMinY - 30.0, easeInOut(sheenP))
                    let sheenAlpha: Double = sin(Double.pi * sheenP) * 0.72
                    let sheenGrad = Gradient(stops: [
                        .init(color: RGBA.white.alpha(0.0).color, location: 0.0),
                        .init(color: chromeBright.alpha(sheenAlpha).color, location: 0.42),
                        .init(color: RGBA.white.alpha(sheenAlpha * 1.15).color, location: 0.52),
                        .init(color: chromeDark.alpha(sheenAlpha * 0.45).color, location: 0.68),
                        .init(color: RGBA.white.alpha(0.0).color, location: 1.0),
                    ])
                    gSheen.fill(
                        Path(CGRect(x: padMinX - 10.0, y: sheenY - 38.0, width: padW + 20.0, height: 76.0)),
                        with: .linearGradient(
                            sheenGrad,
                            startPoint: CGPoint(x: padMidX, y: sheenY - 38.0),
                            endPoint: CGPoint(x: padMidX, y: sheenY + 38.0)
                        )
                    )
                }
            }

            // 3. Detached mercury beads pinching off and snapping upward into the notch.
            let sDrop: UInt32 = seed &+ 503
            let dropCount: Int = 16
            for i in 0..<dropCount {
                let u: Double = 0.12 + closeHash(i, 1, sDrop) * 0.76
                let startT: Double = 0.14 + closeHash(i, 2, sDrop) * 0.40
                let lifeLen: Double = 0.28 + closeHash(i, 3, sDrop) * 0.20
                let life: Double = phase(t, startT, startT + lifeLen)
                if life <= 0.0 || life >= 1.0 { continue }

                let spawnNarrow: Double = easeInOut(phase(startT, 0.16, 0.84)) * 0.7
                let spawnX: Double = lerp(padMinX + u * padW, sinkMidX, spawnNarrow)
                let spawnY: Double = min(padMaxY + 36.0, meltDockedDripY(u, startT, pad, sink, seed) + 4.0)
                let targetX: Double = sinkMidX + (closeHash(i, 4, sDrop) - 0.5) * (sinkW * 0.52)
                let targetY: Double = sinkMinY + 6.0

                let dipAmp: Double = 10.0 + closeHash(i, 5, sDrop) * 14.0
                let dip: Double = sin(Double.pi * min(1.0, life * 2.2)) * dipAmp
                let pull: Double = easeIn(life)
                let cx: Double = lerp(spawnX, targetX, easeInOut(life))
                let cy: Double = lerp(spawnY, targetY, pull) + dip * (1.0 - pull)

                let baseR: Double = 3.2 + closeHash(i, 6, sDrop) * 6.2
                let shrink: Double = 1.0 - easeIn(phase(life, 0.68, 1.0)) * 0.85
                let rx: Double = baseR * shrink * (1.0 - 0.25 * pull)
                let ry: Double = baseR * shrink * (1.0 + 0.65 * pull)
                let alpha: Double = smoothstep(0.0, 0.12, life) * (1.0 - phase(life, 0.85, 1.0))
                meltDrawBead(
                    ctx, cx: cx, cy: cy, rx: rx, ry: ry, stretchY: -pull * 0.9,
                    chromeBright: chromeBright, chromeSilver: chromeSilver, chromeDark: chromeDark, alpha: alpha
                )
            }

            // 4. Final chrome bead slipping into the notch + crisp star-glint.
            let glintLife: Double = phase(t, 0.80, 0.99)
            if glintLife > 0.0 && glintLife < 1.0 {
                let gx: Double = sinkMidX
                let gy: Double = sinkMinY + 8.0
                let pulse: Double = sin(Double.pi * glintLife)
                let lastR: Double = lerp(8.5, 0.8, easeIn(glintLife))
                meltDrawBead(
                    ctx, cx: gx, cy: gy + (1.0 - glintLife) * 6.0, rx: lastR * 1.25, ry: lastR * 0.7, stretchY: 0.0,
                    chromeBright: chromeBright, chromeSilver: chromeSilver, chromeDark: chromeDark, alpha: pulse
                )
                meltDrawStarGlint(ctx, gx: gx, gy: gy, pulse: pulse, maxR: 18.0, chromeBright: chromeBright)
            }
        } else {
            // FLOATING MODE: smooth organic morph from rounded card -> dripping mercury
            // blob -> seamless trembling mercury sphere -> pinpoint star-glint.
            let poolX: Double = padMidX
            let poolY: Double = padMidY + padH * 0.14

            let morphP: Double = easeInOut(phase(t, 0.12, 0.68))
            let shrinkP: Double = easeIn(phase(t, 0.66, 0.96))
            let wobble: Double = sin(t * 24.0) * 0.11 * smoothstep(0.45, 0.68, t) * (1.0 - shrinkP)

            if shrinkP < 0.995 {
                let cx: Double = poolX
                let cy: Double = lerp(padMidY, poolY, morphP)
                let rxBase: Double = lerp(padW * 0.5, 48.0, morphP)
                let ryBase: Double = lerp(padH * 0.5, 42.0, morphP)
                let rx: Double = lerp(rxBase, 1.2, shrinkP) * (1.0 + wobble)
                let ry: Double = lerp(ryBase, 1.2, shrinkP) * (1.0 - wobble)

                let superExp: Double = lerp(6.0, 2.0, smoothstep(0.0, 0.72, morphP))
                let dripAmp: Double = smoothstep(0.04, 0.32, t) * (1.0 - smoothstep(0.46, 0.68, t))
                let s1: UInt32 = seed &+ 41
                let s2: UInt32 = seed &+ 97
                let pHash1: Double = closeHash(2, 1, s1) * 3.0
                let pHash2: Double = closeHash(4, 3, s2) * 3.5

                let pts: Int = 140
                var bodyPath = Path()
                for i in 0..<pts {
                    let ang: Double = (Double(i) / Double(pts)) * Double.pi * 2.0
                    let ca: Double = cos(ang)
                    let sa: Double = sin(ang)
                    let sx: Double = meltSign(ca) * pow(abs(ca), 2.0 / superExp)
                    let sy: Double = meltSign(sa) * pow(abs(sa), 2.0 / superExp)

                    let px: Double = cx + sx * rx
                    var py: Double = cy + sy * ry

                    if dripAmp > 0.005 && sa > 0.05 {
                        let u: Double = 0.5 + sx * 0.5
                        let botMask: Double = pow(max(0.0, sa), 1.5)
                        let w1: Double = pow(0.5 + 0.5 * sin(u * Double.pi * 5.0 + pHash1), 1.8)
                        let w2: Double = pow(0.5 + 0.5 * sin(u * Double.pi * 8.0 + pHash2 + t * 2.0), 2.0)
                        let n: Double = closeNoise(u * 4.0 + 1.1, t * 2.0, s1)
                        py += (w1 * 48.0 + w2 * 20.0 + n * 14.0) * dripAmp * botMask
                    }

                    let pt = CGPoint(x: px, y: py)
                    if i == 0 { bodyPath.move(to: pt) } else { bodyPath.addLine(to: pt) }
                }
                bodyPath.closeSubpath()

                // 1. Melting pad texture inside ONE opacity layer.
                if padReveal > 0.01 {
                    var gPad = ctx
                    gPad.clip(to: bodyPath)
                    gPad.opacity = gPad.opacity * padReveal
                    if t < 0.06 {
                        gPad.clip(to: f.padPath)
                        f.drawPad(gPad, in: pad, opacity: 1.0)
                    } else {
                        let bb: CGRect = bodyPath.boundingRect
                        let bbMinX: Double = Double(bb.minX)
                        let bbMinY: Double = Double(bb.minY)
                        let bbW: Double = Double(bb.width)
                        let bbH: Double = Double(bb.height)
                        gPad.drawLayer { layer in
                            let strips: Int = 24
                            for i in 0..<strips {
                                let u: Double = (Double(i) + 0.5) / Double(strips)
                                let dstX: Double = bbMinX + (Double(i) / Double(strips)) * bbW
                                let dstW: Double = bbW / Double(strips) + 0.6
                                let wBase: Double = 0.5 + 0.5 * sin(u * Double.pi * 5.0 + pHash1)
                                let dripStretch: Double = pow(wBase, 2.0) * 38.0 * dripAmp
                                var gStrip = layer
                                let clipRect = CGRect(x: dstX - 0.2, y: bbMinY - 4.0, width: dstW, height: bbH + 8.0)
                                gStrip.clip(to: Path(clipRect))
                                let mappedRect = CGRect(x: bbMinX, y: bbMinY, width: bbW, height: max(12.0, ry * 2.0 + dripStretch))
                                f.drawPad(gStrip, in: mappedRect, opacity: 1.0)
                            }
                        }
                    }
                }

                // 2. Mirror-chrome shading transitioning seamlessly to spherical bead.
                if metalBlend > 0.01 {
                    let bb: CGRect = bodyPath.boundingRect
                    let bbMinX: Double = Double(bb.minX)
                    let bbMaxX: Double = Double(bb.maxX)
                    let bbMinY: Double = Double(bb.minY)
                    let bbMaxY: Double = Double(bb.maxY)
                    let sphereMix: Double = smoothstep(0.50, 0.72, t)

                    if sphereMix < 0.98 {
                        var gChrome = ctx
                        gChrome.opacity = gChrome.opacity * metalBlend * (1.0 - sphereMix)
                        let horizonShift: Double = sin(t * 7.0) * 0.05
                        let chromeGrad = Gradient(stops: [
                            .init(color: chromeBright.color, location: 0.0),
                            .init(color: chromeSilver.color, location: 0.24),
                            .init(color: chromeDark.color, location: clamp01(0.47 + horizonShift)),
                            .init(color: chromeMid.color, location: clamp01(0.57 + horizonShift)),
                            .init(color: chromeBright.color, location: 0.80),
                            .init(color: chromeDark.mix(chromeMid, 0.35).color, location: 1.0),
                        ])
                        gChrome.fill(
                            bodyPath,
                            with: .linearGradient(
                                chromeGrad,
                                startPoint: CGPoint(x: cx - rx * 0.25, y: bbMinY),
                                endPoint: CGPoint(x: cx + rx * 0.25, y: bbMaxY)
                            )
                        )
                        meltDrawReflections(
                            ctx, bodyPath: bodyPath,
                            bLeft: bbMinX, bRight: bbMaxX, bTop: bbMinY, bBot: bbMaxY,
                            t: t, chromeDark: chromeDark, alpha: metalBlend * (1.0 - sphereMix)
                        )
                    }

                    if sphereMix > 0.02 {
                        let maxR: Double = max(rx, ry) * 1.45
                        let hiPt = CGPoint(x: cx - rx * 0.30, y: cy - ry * 0.32)
                        var gSphere = ctx
                        gSphere.opacity = gSphere.opacity * metalBlend * sphereMix
                        let sphereGrad = Gradient(stops: [
                            .init(color: RGBA.white.color, location: 0.0),
                            .init(color: chromeBright.color, location: 0.22),
                            .init(color: chromeSilver.color, location: 0.48),
                            .init(color: chromeDark.color, location: 0.78),
                            .init(color: chromeSilver.alpha(0.92).color, location: 1.0),
                        ])
                        gSphere.fill(
                            bodyPath,
                            with: .radialGradient(sphereGrad, center: hiPt, startRadius: 0.0, endRadius: CGFloat(maxR))
                        )
                        let sr: Double = max(1.0, rx * 0.24)
                        let specRect = CGRect(x: cx - rx * 0.36 - sr * 0.6, y: cy - ry * 0.36 - sr * 0.45, width: sr * 1.3, height: sr * 0.9)
                        gSphere.fill(Path(ellipseIn: specRect), with: .color(RGBA.white.alpha(0.95).color))
                    }

                    ctx.stroke(bodyPath, with: .color(chromeDark.alpha(0.62 * metalBlend).color), lineWidth: 1.3)
                }

                // Liquefaction sheen sweep.
                let sheenP: Double = phase(t, 0.0, 0.30)
                if sheenP > 0.0 && sheenP < 1.0 {
                    var gSheen = ctx
                    gSheen.clip(to: bodyPath)
                    let sheenY: Double = lerp(padMinY - 30.0, padMaxY + 30.0, easeInOut(sheenP))
                    let sheenAlpha: Double = sin(Double.pi * sheenP) * 0.72
                    let sheenGrad = Gradient(stops: [
                        .init(color: RGBA.white.alpha(0.0).color, location: 0.0),
                        .init(color: chromeBright.alpha(sheenAlpha).color, location: 0.42),
                        .init(color: RGBA.white.alpha(sheenAlpha * 1.15).color, location: 0.52),
                        .init(color: chromeDark.alpha(sheenAlpha * 0.45).color, location: 0.68),
                        .init(color: RGBA.white.alpha(0.0).color, location: 1.0),
                    ])
                    gSheen.fill(
                        Path(CGRect(x: padMinX - 10.0, y: sheenY - 38.0, width: padW + 20.0, height: 76.0)),
                        with: .linearGradient(
                            sheenGrad,
                            startPoint: CGPoint(x: padMidX, y: sheenY - 38.0),
                            endPoint: CGPoint(x: padMidX, y: sheenY + 38.0)
                        )
                    )
                }
            }

            // Detached dripping mercury beads coalescing back into the central bead.
            let sDrop: UInt32 = seed &+ 503
            let dropCount: Int = 14
            for i in 0..<dropCount {
                let u: Double = 0.12 + closeHash(i, 1, sDrop) * 0.76
                let startT: Double = 0.15 + closeHash(i, 2, sDrop) * 0.32
                let lifeLen: Double = 0.28 + closeHash(i, 3, sDrop) * 0.18
                let life: Double = phase(t, startT, startT + lifeLen)
                if life <= 0.0 || life >= 1.0 { continue }

                let spawnX: Double = padMinX + u * padW
                let spawnY: Double = padMaxY + 12.0 + closeHash(i, 6, sDrop) * 24.0
                let fallAmp: Double = 16.0 + closeHash(i, 4, sDrop) * 28.0
                let fallY: Double = spawnY + fallAmp * sin(Double.pi * min(1.0, life * 1.2))
                let pull: Double = easeInOut(phase(life, 0.24, 1.0))
                let cx: Double = lerp(spawnX, poolX, pull)
                let cy: Double = lerp(fallY, poolY + 4.0, pull)

                let baseR: Double = 3.0 + closeHash(i, 5, sDrop) * 5.8
                let rx: Double = baseR * (1.0 - 0.65 * easeIn(life))
                let ry: Double = rx * (1.0 + 0.45 * sin(Double.pi * life))
                let alpha: Double = smoothstep(0.0, 0.12, life) * (1.0 - phase(life, 0.84, 1.0))
                meltDrawBead(
                    ctx, cx: cx, cy: cy, rx: rx, ry: ry, stretchY: 0.5 * (1.0 - pull),
                    chromeBright: chromeBright, chromeSilver: chromeSilver, chromeDark: chromeDark, alpha: alpha
                )
            }

            // Final crisp 4-point chrome specular glint as the last bead vanishes.
            let glintLife: Double = phase(t, 0.84, 0.99)
            if glintLife > 0.0 && glintLife < 1.0 {
                meltDrawStarGlint(ctx, gx: poolX, gy: poolY, pulse: sin(Double.pi * glintLife), maxR: 20.0, chromeBright: chromeBright)
            }
        }
    }
}
