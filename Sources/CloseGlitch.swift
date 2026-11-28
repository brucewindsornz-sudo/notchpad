import SwiftUI

/// Digital signal failure: horizontal slices jump sideways with per-slice RGB chromatic shear,
/// buffer-read repeats, macroblock codec corruption, and hard dropout bursts into the sink.
struct GlitchClose: CloseEffectRenderer {
    let duration: Double = 0.84

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        if f.t <= 0.001 {
            f.drawPad(ctx)
            return
        }

        let t: Double = f.t
        let pad: CGRect = f.pad
        let padMinX: Double = Double(pad.minX)
        let padMaxX: Double = Double(pad.maxX)
        let padMidX: Double = Double(pad.midX)
        let padMinY: Double = Double(pad.minY)
        let padMaxY: Double = Double(pad.maxY)
        let padMidY: Double = Double(pad.midY)
        let padWidth: Double = Double(pad.width)
        let padHeight: Double = Double(pad.height)
        let canvasWidth: Double = Double(f.size.width)
        let sinkY: Double = f.floating ? Double(f.sink.midY) : Double(f.sink.maxY) + 2.0

        // Discrete stepped signal clocks: digital faults snap and hold rather than gliding smoothly.
        let step: Int = Int((t * 22.0).rounded(.down))
        let burstStep: Int = Int((t * 13.0).rounded(.down))

        let intensity: Double = easeOut(phase(t, 0.01, 0.22))
        let collapse: Double = easeIn(phase(t, 0.34, 0.84))
        let bodyAlive: Bool = t < 0.84

        // Iconic digital fault colours harmonised with the pad's theme accent.
        let cyanCol = RGBA(0.04, 0.94, 1.0, 1.0)
        let magCol = RGBA(1.0, 0.08, 0.46, 1.0)
        let darkCut = RGBA(0.03, 0.03, 0.05, 1.0)

        // Brief whole-signal flicker dropout right before total failure.
        let hardDropout: Bool = (t > 0.60 && t < 0.80 && closeHash(step, 91, f.seed) < 0.18)

        // --- Stage 1-4: Torn horizontal slices of the real pad with per-slice RGB chromatic shear ---
        if bodyAlive && !hardDropout {
            let sliceCount: Int = 14
            var yCursor: Double = padMinY
            let baseSliceH: Double = padHeight / Double(sliceCount)

            for i in 0..<sliceCount {
                let hJitter: Double = lerp(0.55, 1.55, closeHash(i, burstStep + 3, f.seed))
                let remaining: Double = padMaxY - yCursor
                let sliceH: Double = (i == sliceCount - 1) ? max(2.0, remaining) : min(remaining, baseSliceH * hJitter)
                let origY0: Double = yCursor
                yCursor += sliceH
                if sliceH <= 1.0 { continue }

                // Staggered packet-loss death time: outer/bottom slices drop out earlier, last strips survive near sink.
                let sliceMidY: Double = origY0 + sliceH * 0.5
                let distNorm: Double = f.floating
                    ? abs(sliceMidY - padMidY) / (padHeight * 0.5)
                    : (sliceMidY - padMinY) / padHeight
                let dieMix: Double = distNorm * 0.58 + closeHash(i, 17, f.seed) * 0.42
                let dieAt: Double = lerp(0.83, 0.42, dieMix)
                if t >= dieAt { continue }

                // Intermittent hard slice dropouts punch clean holes of desktop through the failing signal.
                let dropChance: Double = 0.34 * phase(t, 0.24, 0.74)
                if dropChance > 0.02 && closeHash(i, step + 29, f.seed) < dropChance { continue }

                // Horizontal displacement: most slices jitter, key sheared slices tear violently sideways.
                let shearRoll: Double = closeHash(i, step + 5, f.seed)
                let dir: Double = closeHash(i, step + 13, f.seed) < 0.5 ? -1.0 : 1.0
                let dx: Double
                let rgbSep: Double
                if shearRoll > 0.54 {
                    let normShear: Double = (shearRoll - 0.54) / 0.46
                    let mag: Double = lerp(18.0, 74.0, normShear) * intensity * (1.0 + 0.45 * collapse)
                    dx = dir * mag
                    rgbSep = lerp(6.0, 20.0, closeHash(i, step + 23, f.seed)) * intensity
                } else {
                    dx = (closeHash(i, step + 7, f.seed) - 0.5) * 14.0 * intensity
                    rgbSep = 2.5 * intensity
                }

                // Vertical collapse toward sink (notch lip when docked, centre band when floating).
                let targetMidY: Double = lerp(sliceMidY, sinkY, collapse * 0.88)
                let drawH: Double = max(2.0, sliceH * lerp(1.0, 0.30, collapse))
                let drawY: Double = f.floating ? (targetMidY - drawH * 0.5) : max(padMinY, targetMidY - drawH * 0.5)
                let dyShift: Double = drawY - origY0

                // Buffer-read repeat corruption: ~26% of slices sample from the wrong vertical offset of the pad.
                var srcOffsetY: Double = 0.0
                if t > 0.10 && closeHash(i, burstStep + 41, f.seed) < 0.26 {
                    srcOffsetY = (closeHash(i, burstStep + 47, f.seed) - 0.5) * 95.0
                }

                let sliceBand = CGRect(x: 0.0, y: drawY, width: canvasWidth, height: drawH)
                let padDrawRect = CGRect(
                    x: padMinX + dx,
                    y: padMinY + dyShift + srcOffsetY,
                    width: padWidth,
                    height: padHeight
                )
                let shiftedBounds = CGRect(x: padMinX + dx, y: padMinY + dyShift, width: padWidth, height: padHeight)
                let shiftedPadPath: Path = f.padPath(in: shiftedBounds)

                // Chromatic RGB split ghosts on sheared slices (magenta left, cyan right).
                if rgbSep > 3.2 {
                    let ghostOpacity: Double = f.dark ? 0.72 : 0.44

                    let redBounds = CGRect(x: padMinX + dx - rgbSep, y: padMinY + dyShift, width: padWidth, height: padHeight)
                    let redDrawRect = CGRect(x: Double(padDrawRect.minX) - rgbSep, y: Double(padDrawRect.minY), width: padWidth, height: padHeight)
                    var gRed = ctx
                    gRed.clip(to: Path(sliceBand))
                    gRed.clip(to: f.padPath(in: redBounds))
                    gRed.blendMode = f.dark ? .plusLighter : .normal
                    gRed.addFilter(.colorMultiply(magCol.color))
                    f.drawPad(gRed, in: redDrawRect, opacity: ghostOpacity)

                    let cyanBounds = CGRect(x: padMinX + dx + rgbSep, y: padMinY + dyShift, width: padWidth, height: padHeight)
                    let cyanDrawRect = CGRect(x: Double(padDrawRect.minX) + rgbSep, y: Double(padDrawRect.minY), width: padWidth, height: padHeight)
                    var gCyan = ctx
                    gCyan.clip(to: Path(sliceBand))
                    gCyan.clip(to: f.padPath(in: cyanBounds))
                    gCyan.blendMode = f.dark ? .plusLighter : .normal
                    gCyan.addFilter(.colorMultiply(cyanCol.color))
                    f.drawPad(gCyan, in: cyanDrawRect, opacity: ghostOpacity)

                    // Crisp chromatic edge-fringes on sheared slice boundaries (essential for pure-black themes like notch).
                    let fringeW: Double = min(6.0, rgbSep * 0.45)
                    let edgeY: Double = drawY + 1.0
                    let edgeH: Double = max(1.5, drawH - 2.0)
                    let inset: Double = f.floating ? 4.0 : 12.0
                    let leftFringe = CGRect(x: padMinX + dx + inset - fringeW, y: edgeY, width: fringeW, height: edgeH)
                    let rightFringe = CGRect(x: padMaxX + dx - inset, y: edgeY, width: fringeW, height: edgeH)
                    ctx.fill(Path(leftFringe), with: .color(magCol.alpha(0.75).color))
                    ctx.fill(Path(rightFringe), with: .color(cyanCol.alpha(0.75).color))
                }

                // Main torn slice of the real pad (hard digital alpha, no soft fade).
                var gSlice = ctx
                gSlice.clip(to: Path(sliceBand))
                gSlice.clip(to: shiftedPadPath)
                if t > 0.24 && t < 0.74 && closeHash(i, step + 61, f.seed) < 0.11 {
                    gSlice.addFilter(.colorInvert(1.0))
                }
                f.drawPad(gSlice, in: padDrawRect, opacity: 1.0)

                // Crisp scanlines clipped ONLY inside surviving slices (never floating over empty desktop).
                if drawH >= 5.0 {
                    var scanPath = Path()
                    var sy: Double = drawY + Double(step % 2) * 2.0
                    let syEnd: Double = drawY + drawH
                    while sy < syEnd {
                        scanPath.addRect(CGRect(x: padMinX + dx, y: sy, width: padWidth, height: 1.1))
                        sy += 4.0
                    }
                    gSlice.fill(scanPath, with: .color(RGBA(0.0, 0.0, 0.0, 0.24 * intensity).color))
                }
            }
        }

        // --- Stage 2-4: Crisp macroblock codec corruption & pixel-sort streaks (hard digital cut, no mushy fade) ---
        if t > 0.05 && t < 0.87 {
            let blockProgress: Double = easeOut(phase(t, 0.05, 0.35)) * (1.0 - easeIn(phase(t, 0.62, 0.87)))
            let blockCount: Int = Int(lerp(2.0, 24.0, blockProgress).rounded(.down))
            let activeTop: Double = f.floating ? lerp(padMinY, sinkY - 20.0, collapse * 0.88) : padMinY
            let activeBot: Double = lerp(padMaxY, sinkY + 20.0, collapse * 0.88)
            let activeH: Double = max(10.0, activeBot - activeTop)
            let sizeScale: Double = lerp(1.0, 0.45, phase(t, 0.66, 0.87))

            if blockCount > 0 {
                for b in 0..<blockCount {
                    let seedK: Int = burstStep * 31 + b
                    let rx: Double = closeHash(b, seedK + 1, f.seed)
                    let ry: Double = closeHash(b, seedK + 2, f.seed)
                    let rw: Double = closeHash(b, seedK + 3, f.seed)
                    let rh: Double = closeHash(b, seedK + 4, f.seed)
                    let kindRoll: Double = closeHash(b, seedK + 5, f.seed)

                    // Snap macroblocks to an 8pt digital codec grid.
                    let rawW: Double = lerp(16.0, 68.0, rw) * sizeScale
                    let rawH: Double = lerp(6.0, 20.0, rh) * sizeScale
                    let bw: Double = max(8.0, (rawW / 8.0).rounded(.down) * 8.0)
                    let bh: Double = max(4.0, (rawH / 4.0).rounded(.down) * 4.0)
                    let bxSpan: Double = padWidth + 48.0 - bw
                    let bySpan: Double = max(4.0, activeH - bh)
                    let bx: Double = padMinX - 24.0 + ((rx * bxSpan) / 8.0).rounded(.down) * 8.0
                    let by: Double = activeTop + ((ry * bySpan) / 4.0).rounded(.down) * 4.0

                    if !f.floating && by < padMinY { continue }

                    let col: RGBA
                    if kindRoll < 0.42 {
                        let cCol: Int = min(f.cells.cols - 1, max(0, Int((rx * Double(f.cells.cols)).rounded(.down))))
                        let cRow: Int = min(f.cells.rows - 1, max(0, Int((ry * Double(f.cells.rows)).rounded(.down))))
                        let sampled: RGBA = f.cells.color(cCol, cRow)
                        col = sampled.a > 0.1 ? sampled.alpha(0.94) : f.bg.alpha(0.92)
                    } else if kindRoll < 0.62 {
                        col = cyanCol.alpha(0.92)
                    } else if kindRoll < 0.80 {
                        col = magCol.alpha(0.92)
                    } else if kindRoll < 0.91 {
                        col = darkCut.alpha(0.95)
                    } else {
                        col = f.accent.mix(RGBA.white, 0.35).alpha(0.94)
                    }

                    ctx.fill(Path(CGRect(x: bx, y: by, width: bw, height: bh)), with: .color(col.color))

                    // Offset chromatic ghost bar on fault blocks.
                    if kindRoll >= 0.42 && kindRoll < 0.80 {
                        let ghostCol: RGBA = kindRoll < 0.62 ? magCol : cyanCol
                        let gShift: Double = kindRoll < 0.62 ? -5.0 : 5.0
                        let ghostRect = CGRect(x: bx + gShift, y: by + 2.0, width: bw * 0.65, height: max(2.0, bh * 0.35))
                        ctx.fill(Path(ghostRect), with: .color(ghostCol.alpha(0.78).color))
                    }
                }
            }

            // Horizontal pixel-sort / tear streaks shooting out past the pad edges into the bleed area.
            let streakCount: Int = max(1, Int(lerp(2.0, 7.0, blockProgress).rounded(.down)))
            for s in 0..<streakCount {
                let sy: Double = activeTop + closeHash(s, step + 71, f.seed) * activeH
                if !f.floating && sy < padMinY { continue }
                let sh: Double = lerp(1.5, 3.8, closeHash(s, step + 73, f.seed))
                let sw: Double = lerp(55.0, 200.0, closeHash(s, step + 79, f.seed)) * (1.0 - 0.40 * collapse)
                let sx: Double = padMinX - 48.0 + closeHash(s, step + 83, f.seed) * (padWidth + 96.0 - sw)
                let sKind: Double = closeHash(s, step + 89, f.seed)
                let sCol: RGBA
                if sKind < 0.36 {
                    sCol = cyanCol.alpha(0.88)
                } else if sKind < 0.68 {
                    sCol = magCol.alpha(0.86)
                } else if sKind < 0.86 {
                    sCol = RGBA.white.alpha(0.90)
                } else {
                    sCol = darkCut.alpha(0.90)
                }
                ctx.fill(Path(CGRect(x: sx, y: sy, width: sw, height: sh)), with: .color(sCol.color))
            }
        }

        // --- Stage 5: Dead-signal snap-out at the sink (t = 0.74 -> 0.96, crisp digital cut) ---
        if t >= 0.74 && t < 0.96 {
            let tailP: Double = phase(t, 0.74, 0.96)
            // Hard staccato blink: snaps out cleanly on the last beat with zero mushy fade.
            let blinkOn: Bool = (t < 0.85) || (closeHash(step, 107, f.seed) > 0.25)
            if blinkOn {
                let tailW: Double = lerp(padWidth * 0.72, 36.0, easeIn(tailP))
                let tailShift: Double = (closeHash(step, 113, f.seed) - 0.5) * 40.0 * (1.0 - tailP)
                let lx: Double = padMidX - tailW * 0.5 + tailShift
                let ly: Double = f.floating ? sinkY : max(padMinY + 4.0, sinkY - 6.0 * tailP)

                // Dark contrast backing strip so the final snap reads crisply on white desktops.
                ctx.fill(Path(CGRect(x: lx - 4.0, y: ly - 2.5, width: tailW + 8.0, height: 5.5)), with: .color(darkCut.alpha(0.55).color))

                // Chromatic cyan + magenta offset signal tear lines.
                ctx.fill(Path(CGRect(x: lx - 7.0, y: ly - 1.5, width: tailW * 0.84, height: 2.0)), with: .color(magCol.alpha(0.92).color))
                ctx.fill(Path(CGRect(x: lx + 7.0, y: ly + 0.5, width: tailW * 0.84, height: 2.0)), with: .color(cyanCol.alpha(0.94).color))

                // Razor white core tear line.
                ctx.fill(Path(CGRect(x: lx, y: ly - 0.8, width: tailW, height: 1.8)), with: .color(RGBA.white.alpha(0.96).color))

                // Crisp snapping data flecks around the sink.
                let fleckCount: Int = t < 0.88 ? 4 : 2
                for k in 0..<fleckCount {
                    let fx: Double = padMidX + (closeHash(k, step + 127, f.seed) - 0.5) * tailW * 1.15
                    let fy: Double = ly + (closeHash(k, step + 131, f.seed) - 0.5) * 18.0
                    if !f.floating && fy < padMinY { continue }
                    let fw: Double = lerp(8.0, 22.0, closeHash(k, step + 137, f.seed)) * (1.0 - 0.5 * tailP)
                    let fh: Double = lerp(2.5, 5.5, closeHash(k, step + 139, f.seed))
                    let fCol: RGBA = k == 0 ? cyanCol : (k == 1 ? magCol : (k == 2 ? darkCut : RGBA.white))
                    ctx.fill(Path(CGRect(x: fx, y: fy, width: fw, height: fh)), with: .color(fCol.alpha(0.94).color))
                }
            }
        }
    }
}
