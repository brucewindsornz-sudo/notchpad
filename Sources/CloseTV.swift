import SwiftUI

// Tapered horizontal spindle (thickest at centre, needle-sharp at left & right tips).
private func tvSpindlePath(cx: Double, cy: Double, halfW: Double, halfH: Double) -> Path {
    var p = Path()
    if halfW <= 0.1 || halfH <= 0.05 { return p }
    p.move(to: CGPoint(x: cx - halfW, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx + halfW, y: cy), control: CGPoint(x: cx, y: cy - halfH * 1.8))
    p.addQuadCurve(to: CGPoint(x: cx - halfW, y: cy), control: CGPoint(x: cx, y: cy + halfH * 1.8))
    p.closeSubpath()
    return p
}

// Tapered vertical spindle for the phosphor dot's diffraction cross-glint.
private func tvVerticalSpindlePath(cx: Double, cy: Double, halfW: Double, halfH: Double) -> Path {
    var p = Path()
    if halfW <= 0.05 || halfH <= 0.1 { return p }
    p.move(to: CGPoint(x: cx, y: cy - halfH))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy + halfH), control: CGPoint(x: cx + halfW * 1.8, y: cy))
    p.addQuadCurve(to: CGPoint(x: cx, y: cy - halfH), control: CGPoint(x: cx - halfW * 1.8, y: cy))
    p.closeSubpath()
    return p
}

/// Old CRT television switching off: vertical deflection collapses with 3-gun RGB convergence
/// slip and scanlines into a searing horizontal beam, snapping to a glowing phosphor dot.
struct TVClose: CloseEffectRenderer {
    let duration: Double = 0.85

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        if f.t <= 0.001 {
            f.drawPad(ctx)
            return
        }

        let t: Double = f.t
        let pad: CGRect = f.pad
        let padMinY: Double = Double(pad.minY)
        let padMidY: Double = Double(pad.midY)
        let padWidth: Double = Double(pad.width)
        let padHeight: Double = Double(pad.height)
        let cx: Double = Double(pad.midX)

        // Stage 1-2: Vertical deflection collapses quickly from the first frames into a razor line.
        let vRaw: Double = phase(t, 0.01, 0.45)
        let vEase: Double = lerp(easeIn(vRaw), easeInOut(vRaw), 0.62)

        // Stage 2-3: Capacitor-surge horizontal bloom (+3% width), then horizontal coil snaps to a dot.
        let surge: Double = sin(Double.pi * phase(t, 0.02, 0.40))
        let hRaw: Double = phase(t, 0.41, 0.72)
        let hEase: Double = easeInOut(hRaw)

        // Target Y: floating collapses at pad centre; docked collapses cleanly to the notch lip and tucks in.
        let sinkY: Double = f.floating ? Double(f.sink.midY) : Double(f.sink.maxY) + 4.0
        let cyLift: Double = easeInOut(phase(t, 0.04, 0.50))
        var cy: Double = lerp(padMidY, sinkY, cyLift)
        if !f.floating {
            cy = cy - 10.0 * easeIn(phase(t, 0.74, 1.0))
        }

        let w: Double = lerp(padWidth * (1.0 + 0.03 * surge), 4.0, hEase)
        let h: Double = lerp(padHeight, 2.4, vEase)

        // Subtle horizontal sync jitter as the power supply cuts out.
        let joltEnv: Double = sin(Double.pi * phase(t, 0.01, 0.24))
        let joltStep: Int = Int((t * 30.0).rounded(.down))
        let joltX: Double = (closeHash(joltStep, 11, f.seed) - 0.5) * 7.0 * joltEnv

        let topY: Double = f.floating ? (cy - h * 0.5) : max(padMinY, cy - h * 0.5)
        let r = CGRect(x: cx - w * 0.5 + joltX, y: topY, width: w, height: h)
        let rMinX: Double = Double(r.minX)
        let rMinY: Double = Double(r.minY)
        let rMaxY: Double = Double(r.maxY)
        let rMidX: Double = Double(r.midX)
        let rWidth: Double = Double(r.width)
        let rHeight: Double = Double(r.height)
        let beamCy: Double = Double(r.midY)

        // Iconic CRT P4/P22 phosphor cyan-white, harmonised with the pad's theme accent.
        let crtCyan = RGBA(0.60, 0.90, 1.0, 1.0)
        let crtAccent: RGBA = crtCyan.mix(f.accent, 0.38)
        let crtDeep: RGBA = RGBA(0.18, 0.52, 0.80, 1.0).mix(f.accent, 0.40)

        // --- Stage 1 & 2: Collapsing pad with 3-gun RGB convergence slip, scanlines & beam concentration ---
        let padFade: Double = 1.0 - phase(t, 0.38, 0.51)
        if padFade > 0.005 {
            let clipPath: Path = f.padPath(in: r)
            var gPad = ctx
            gPad.clip(to: clipPath)

            // Main collapsing pad picture, brightening smoothly as vertical scanlines pack together.
            var gMain = gPad
            let boost: Double = (f.dark ? 0.42 : 0.25) * easeIn(vRaw)
            if boost > 0.01 {
                gMain.addFilter(.brightness(boost))
            }
            f.drawPad(gMain, in: r, opacity: padFade)

            // 3-gun RGB convergence slip: red & cyan guns lose vertical deflection at slightly different rates.
            let splitAmt: Double = sin(Double.pi * phase(t, 0.02, 0.44))
            if splitAmt > 0.02 && h > 5.0 {
                let rShiftX: Double = -5.5 * splitAmt
                let rExtraH: Double = h * 0.09 * splitAmt
                let rRect = CGRect(x: rMinX + rShiftX, y: rMinY - rExtraH * 0.5, width: rWidth, height: rHeight + rExtraH)
                var gRed = gPad
                gRed.blendMode = f.dark ? .plusLighter : .multiply
                gRed.addFilter(.colorMultiply(RGBA(1.0, 0.20, 0.30, 1.0).color))
                let splitAlpha: Double = (f.dark ? 0.52 : 0.24) * splitAmt * padFade
                f.drawPad(gRed, in: rRect, opacity: splitAlpha)

                let bShiftX: Double = 5.5 * splitAmt
                let bShrinkH: Double = h * 0.08 * splitAmt
                let bRect = CGRect(x: rMinX + bShiftX, y: rMinY + bShrinkH * 0.5, width: rWidth, height: max(2.0, rHeight - bShrinkH))
                var gBlue = gPad
                gBlue.blendMode = f.dark ? .plusLighter : .multiply
                gBlue.addFilter(.colorMultiply(RGBA(0.15, 0.90, 1.0, 1.0).color))
                f.drawPad(gBlue, in: bRect, opacity: splitAlpha)
            }

            // Crisp horizontal CRT scanlines merged into one path fill.
            let scanIn: Double = easeOut(phase(t, 0.01, 0.14)) * (1.0 - phase(t, 0.36, 0.48))
            if scanIn > 0.01 && h > 8.0 {
                var scanPath = Path()
                let pitch: Double = 3.5
                var sy: Double = rMinY + 1.0
                while sy < rMaxY {
                    scanPath.addRect(CGRect(x: rMinX, y: sy, width: rWidth, height: 1.25))
                    sy += pitch
                }
                let scanAlpha: Double = (f.dark ? 0.36 : 0.24) * scanIn * padFade
                gPad.fill(scanPath, with: .color(RGBA(0.0, 0.0, 0.0, scanAlpha).color))
            }

            // Brief analog retrace/static flicker lines sweeping inside the collapsing tube.
            let retraceEnv: Double = sin(Double.pi * phase(t, 0.03, 0.42))
            if retraceEnv > 0.05 && h > 10.0 {
                var retracePath = Path()
                let step: Int = Int((t * 24.0).rounded(.down))
                for i in 0..<3 {
                    let ny: Double = closeHash(step, i + 31, f.seed)
                    let ly: Double = rMinY + ny * rHeight
                    retracePath.addRect(CGRect(x: rMinX, y: ly, width: rWidth, height: 1.0))
                }
                let retraceCol: RGBA = crtAccent.mix(RGBA.white, 0.6).alpha(0.32 * retraceEnv * padFade)
                gPad.fill(retracePath, with: .color(retraceCol.color))
            }

            // Tube edge darkening + luminous phosphor concentration band along the horizontal midline.
            let vigAlpha: Double = easeOut(phase(t, 0.04, 0.30)) * padFade
            let coreGlow: Double = easeIn(phase(t, 0.10, 0.44)) * padFade
            let edgeDark: Double = f.dark ? 0.48 : 0.28
            let edgeCol = RGBA(0.01, 0.02, 0.05, edgeDark * vigAlpha)
            let edgeClear = RGBA(0.01, 0.02, 0.05, 0.0)
            let midCol: RGBA = crtAccent.mix(RGBA.white, 0.72).alpha(0.92 * coreGlow)
            let grad = Gradient(stops: [
                .init(color: edgeCol.color, location: 0.0),
                .init(color: edgeClear.color, location: 0.22),
                .init(color: midCol.color, location: 0.50),
                .init(color: edgeClear.color, location: 0.78),
                .init(color: edgeCol.color, location: 1.0)
            ])
            gPad.fill(clipPath, with: .linearGradient(grad, startPoint: CGPoint(x: rMidX, y: rMinY), endPoint: CGPoint(x: rMidX, y: rMaxY)))

            // Power-cut surge: crisp luminous central scan-band instead of a flat grey wash.
            let initFlash: Double = sin(Double.pi * phase(t, 0.005, 0.14))
            if initFlash > 0.01 {
                let bandH: Double = max(6.0, rHeight * 0.28)
                let bandGrad = Gradient(stops: [
                    .init(color: crtAccent.alpha(0.0).color, location: 0.0),
                    .init(color: RGBA.white.alpha(0.34 * initFlash).color, location: 0.5),
                    .init(color: crtAccent.alpha(0.0).color, location: 1.0)
                ])
                let bandRect = CGRect(x: rMinX, y: beamCy - bandH * 0.5, width: rWidth, height: bandH)
                gPad.fill(
                    Path(bandRect),
                    with: .linearGradient(bandGrad, startPoint: CGPoint(x: rMidX, y: beamCy - bandH * 0.5), endPoint: CGPoint(x: rMidX, y: beamCy + bandH * 0.5))
                )
            }
        }

        // --- Stage 3: Searing horizontal electron beam & bloom ---
        let beamIn: Double = easeOut(phase(t, 0.24, 0.43))
        let beamOut: Double = 1.0 - phase(t, 0.69, 0.76)
        let beamAlpha: Double = beamIn * beamOut

        if beamAlpha > 0.005 {
            let halfW: Double = w * 0.5
            let energy: Double = 1.0 + 0.5 * sin(Double.pi * phase(t, 0.42, 0.74))
            let coreHalfH: Double = lerp(2.3, 1.4, hEase) * (0.85 + 0.25 * energy)
            let beamCx: Double = cx + joltX

            // Soft cool-tinted contrast backing so the white-hot beam reads vividly on white desktops too.
            var gBack = ctx
            if !testNoEffects {
                gBack.addFilter(.blur(radius: 5))
            }
            let backBeamCol: RGBA = crtDeep.mix(RGBA.black, 0.55).alpha(0.32 * beamAlpha)
            gBack.fill(
                tvSpindlePath(cx: beamCx, cy: beamCy, halfW: halfW + 8.0, halfH: coreHalfH + 3.6),
                with: .color(backBeamCol.color)
            )

            // Wide + inner phosphor bloom in one blurred additive layer.
            var gBloom = ctx
            gBloom.blendMode = .plusLighter
            if !testNoEffects {
                gBloom.addFilter(.blur(radius: 9))
            }
            let outerBloomCol: RGBA = crtAccent.alpha(0.82 * beamAlpha)
            let innerBloomCol: RGBA = RGBA.white.alpha(0.62 * beamAlpha)
            gBloom.drawLayer { layer in
                layer.fill(
                    tvSpindlePath(cx: beamCx, cy: beamCy, halfW: halfW + 14.0, halfH: coreHalfH * 3.4),
                    with: .color(outerBloomCol.color)
                )
                layer.fill(
                    tvSpindlePath(cx: beamCx, cy: beamCy, halfW: halfW * 0.78, halfH: coreHalfH * 1.9),
                    with: .color(innerBloomCol.color)
                )
            }

            // Crisp unblurred needle-sharp white-hot core.
            let tipCol: RGBA = crtAccent.alpha(0.0)
            let shoulderCol: RGBA = crtAccent.mix(RGBA.white, 0.72).alpha(0.95 * beamAlpha)
            let centreCol: RGBA = RGBA.white.alpha(beamAlpha)
            let beamGrad = Gradient(stops: [
                .init(color: tipCol.color, location: 0.0),
                .init(color: shoulderCol.color, location: 0.12),
                .init(color: centreCol.color, location: 0.50),
                .init(color: shoulderCol.color, location: 0.88),
                .init(color: tipCol.color, location: 1.0)
            ])
            ctx.fill(
                tvSpindlePath(cx: beamCx, cy: beamCy, halfW: halfW + 2.0, halfH: coreHalfH),
                with: .linearGradient(beamGrad, startPoint: CGPoint(x: cx - halfW - 2.0, y: beamCy), endPoint: CGPoint(x: cx + halfW + 2.0, y: beamCy))
            )
        }

        // --- Stage 4 & 5: Phosphor dot flare, diffraction cross-glint & deliberate lingering afterglow ---
        let dotIn: Double = easeOut(phase(t, 0.62, 0.71))
        let dotOut: Double = 1.0 - phase(t, 0.73, 1.0)
        if dotIn > 0.005 && dotOut > 0.005 {
            let flare: Double = sin(Double.pi * phase(t, 0.63, 0.82))
            let coreLife: Double = pow(clamp01(1.0 - phase(t, 0.72, 0.96)), 1.35)
            let glowLife: Double = pow(clamp01(dotOut), 1.15)

            // Phosphor cools visibly from pure white -> vivid cyan-accent -> deep ember before winking out.
            let coolT: Double = easeOut(phase(t, 0.72, 0.98))
            let haloColor: RGBA = crtAccent.mix(crtDeep, coolT)
            let dotPos = CGPoint(x: cx, y: beamCy)

            // Subtle tinted contrast backing for light/white desktops.
            let backR: Double = lerp(17.0, 5.0, coolT) * dotIn
            if backR > 0.5 {
                let backCol: RGBA = crtDeep.mix(RGBA.black, 0.45)
                let backGrad = Gradient(stops: [
                    .init(color: backCol.alpha(0.28 * glowLife * dotIn).color, location: 0.0),
                    .init(color: backCol.alpha(0.0).color, location: 1.0)
                ])
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - backR, y: beamCy - backR, width: backR * 2.0, height: backR * 2.0)),
                    with: .radialGradient(backGrad, center: dotPos, startRadius: 0, endRadius: CGFloat(backR))
                )
            }

            // Outer lingering phosphor afterglow halo (radial gradient = fast, zero extra blur).
            let outerR: Double = lerp(30.0, 8.0, coolT) * dotIn + 14.0 * flare
            let outerC0: RGBA = RGBA.white.mix(haloColor, 0.35 + 0.60 * coolT).alpha(0.92 * glowLife * dotIn)
            let outerC1: RGBA = haloColor.alpha(0.52 * glowLife * dotIn)
            let outerC2: RGBA = crtDeep.alpha(0.18 * glowLife * dotIn)
            let outerC3: RGBA = crtDeep.alpha(0.0)
            let outerGrad = Gradient(stops: [
                .init(color: outerC0.color, location: 0.0),
                .init(color: outerC1.color, location: 0.34),
                .init(color: outerC2.color, location: 0.68),
                .init(color: outerC3.color, location: 1.0)
            ])
            var gGlow = ctx
            gGlow.blendMode = .plusLighter
            gGlow.fill(
                Path(ellipseIn: CGRect(x: cx - outerR, y: beamCy - outerR, width: outerR * 2.0, height: outerR * 2.0)),
                with: .radialGradient(outerGrad, center: dotPos, startRadius: 0, endRadius: CGFloat(outerR))
            )

            // Brief diffraction cross-glint right when the horizontal beam snaps into the dot.
            if flare > 0.02 {
                gGlow.fill(
                    tvSpindlePath(cx: cx, cy: beamCy, halfW: 36.0 * flare, halfH: 1.5 * flare),
                    with: .color(RGBA.white.alpha(0.88 * flare).color)
                )
                let vGlintCol: RGBA = crtAccent.mix(RGBA.white, 0.65).alpha(0.74 * flare)
                gGlow.fill(
                    tvVerticalSpindlePath(cx: cx, cy: beamCy, halfW: 1.3 * flare, halfH: 16.0 * flare),
                    with: .color(vGlintCol.color)
                )
            }

            // Crisp phosphor core bead that shrinks smoothly and cools to a glowing ember.
            let coreR: Double = lerp(6.0, 1.0, easeOut(phase(t, 0.72, 0.98))) * dotIn + 2.2 * flare
            if coreR > 0.3 && glowLife > 0.01 {
                let coreAlpha: Double = max(coreLife, glowLife * 0.75) * dotIn
                let coreColor: RGBA = RGBA.white.mix(haloColor, coolT * 0.60).alpha(coreAlpha)
                ctx.fill(
                    Path(ellipseIn: CGRect(x: cx - coreR, y: beamCy - coreR, width: coreR * 2.0, height: coreR * 2.0)),
                    with: .color(coreColor.color)
                )
            }
        }
    }
}
