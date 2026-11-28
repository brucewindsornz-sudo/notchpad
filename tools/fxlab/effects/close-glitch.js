export const kind = 'close';
export const duration = 0.84;

export function draw(f, ctx) {
  if (f.t <= 0.001) {
    f.drawPad(ctx);
    return;
  }

  const t = f.t;
  const pad = f.pad;
  const sinkY = f.floating ? f.sink.midY : f.sink.maxY + 2;

  // Discrete stepped signal clocks: digital faults snap and hold rather than gliding smoothly.
  const step = Math.floor(t * 22);
  const burstStep = Math.floor(t * 13);

  const intensity = easeOut(phase(t, 0.01, 0.22));
  const collapse = easeIn(phase(t, 0.34, 0.84));
  const bodyAlive = t < 0.84;

  // Iconic digital fault colours harmonised with the pad's theme accent.
  const cyanCol = new RGBA(0.04, 0.94, 1.0, 1);
  const magCol = new RGBA(1.0, 0.08, 0.46, 1);
  const darkCut = new RGBA(0.03, 0.03, 0.05, 1);

  // Brief whole-signal flicker dropout right before total failure.
  const hardDropout = (t > 0.60 && t < 0.80 && closeHash(step, 91, f.seed) < 0.18);

  // --- Stage 1-4: Torn horizontal slices of the real pad with per-slice RGB chromatic shear ---
  if (bodyAlive && !hardDropout) {
    const sliceCount = 14;
    let yCursor = pad.minY;
    const baseSliceH = pad.height / sliceCount;

    for (let i = 0; i < sliceCount; i++) {
      const hJitter = lerp(0.55, 1.55, closeHash(i, burstStep + 3, f.seed));
      const sliceH = (i === sliceCount - 1) ? Math.max(2, pad.maxY - yCursor) : Math.min(pad.maxY - yCursor, baseSliceH * hJitter);
      const origY0 = yCursor;
      yCursor += sliceH;
      if (sliceH <= 1) continue;

      // Staggered packet-loss death time: outer/bottom slices drop out earlier, last strips survive near sink.
      const distNorm = f.floating
        ? Math.abs((origY0 + sliceH * 0.5) - pad.midY) / (pad.height * 0.5)
        : (origY0 + sliceH * 0.5 - pad.minY) / pad.height;
      const dieAt = lerp(0.83, 0.42, distNorm * 0.58 + closeHash(i, 17, f.seed) * 0.42);
      if (t >= dieAt) continue;

      // Intermittent hard slice dropouts punch clean holes of desktop through the failing signal.
      const dropChance = 0.34 * phase(t, 0.24, 0.74);
      if (dropChance > 0.02 && closeHash(i, step + 29, f.seed) < dropChance) continue;

      // Horizontal displacement: most slices jitter, key sheared slices tear violently sideways.
      const shearRoll = closeHash(i, step + 5, f.seed);
      const dir = closeHash(i, step + 13, f.seed) < 0.5 ? -1 : 1;
      let dx = 0;
      let rgbSep = 0;
      if (shearRoll > 0.54) {
        const mag = lerp(18, 74, (shearRoll - 0.54) / 0.46) * intensity * (1 + 0.45 * collapse);
        dx = dir * mag;
        rgbSep = lerp(6, 20, closeHash(i, step + 23, f.seed)) * intensity;
      } else {
        dx = (closeHash(i, step + 7, f.seed) - 0.5) * 14 * intensity;
        rgbSep = 2.5 * intensity;
      }

      // Vertical collapse toward sink (notch lip when docked, centre band when floating).
      const sliceMidY = origY0 + sliceH * 0.5;
      const targetMidY = lerp(sliceMidY, sinkY, collapse * 0.88);
      const drawH = Math.max(2, sliceH * lerp(1.0, 0.30, collapse));
      const drawY = f.floating ? (targetMidY - drawH * 0.5) : Math.max(pad.minY, targetMidY - drawH * 0.5);
      const dyShift = drawY - origY0;

      // Buffer-read repeat corruption: ~26% of slices sample from the wrong vertical offset of the pad.
      let srcOffsetY = 0;
      if (t > 0.10 && closeHash(i, burstStep + 41, f.seed) < 0.26) {
        srcOffsetY = (closeHash(i, burstStep + 47, f.seed) - 0.5) * 95;
      }

      const sliceBand = new CGRect(0, drawY, f.size.width, drawH);
      const padDrawRect = new CGRect(
        pad.minX + dx,
        pad.minY + dyShift + srcOffsetY,
        pad.width,
        pad.height
      );
      const shiftedPadPath = f.padPathIn(new CGRect(pad.minX + dx, pad.minY + dyShift, pad.width, pad.height));

      // Chromatic RGB split ghosts on sheared slices (magenta left, cyan right).
      if (rgbSep > 3.2) {
        const gRed = ctx.copy();
        gRed.clip(Path.rect(sliceBand));
        gRed.clip(f.padPathIn(new CGRect(pad.minX + dx - rgbSep, pad.minY + dyShift, pad.width, pad.height)));
        gRed.blendMode = f.dark ? 'plusLighter' : 'normal';
        gRed.addFilter(Filter.colorMultiply(magCol));
        f.drawPad(gRed, new CGRect(padDrawRect.minX - rgbSep, padDrawRect.minY, pad.width, pad.height), f.dark ? 0.72 : 0.44);

        const gCyan = ctx.copy();
        gCyan.clip(Path.rect(sliceBand));
        gCyan.clip(f.padPathIn(new CGRect(pad.minX + dx + rgbSep, pad.minY + dyShift, pad.width, pad.height)));
        gCyan.blendMode = f.dark ? 'plusLighter' : 'normal';
        gCyan.addFilter(Filter.colorMultiply(cyanCol));
        f.drawPad(gCyan, new CGRect(padDrawRect.minX + rgbSep, padDrawRect.minY, pad.width, pad.height), f.dark ? 0.72 : 0.44);

        // Crisp chromatic edge-fringes on sheared slice boundaries (essential for pure-black themes like notch).
        const fringeW = Math.min(6, rgbSep * 0.45);
        const edgeY = drawY + 1;
        const edgeH = Math.max(1.5, drawH - 2);
        const inset = f.floating ? 4 : 12;
        ctx.fill(Path.rect(new CGRect(pad.minX + dx + inset - fringeW, edgeY, fringeW, edgeH)), Shading.color(magCol.alpha(0.75)));
        ctx.fill(Path.rect(new CGRect(pad.maxX + dx - inset, edgeY, fringeW, edgeH)), Shading.color(cyanCol.alpha(0.75)));
      }

      // Main torn slice of the real pad (hard digital alpha, no soft fade).
      const gSlice = ctx.copy();
      gSlice.clip(Path.rect(sliceBand));
      gSlice.clip(shiftedPadPath);
      if (t > 0.24 && t < 0.74 && closeHash(i, step + 61, f.seed) < 0.11) {
        gSlice.addFilter(Filter.colorInvert(1));
      }
      f.drawPad(gSlice, padDrawRect, 1.0);

      // Crisp scanlines clipped ONLY inside surviving slices (never floating over empty desktop).
      if (drawH >= 5) {
        const scanPath = new Path();
        let sy = drawY + (step % 2) * 2.0;
        while (sy < drawY + drawH) {
          scanPath.addRect(new CGRect(pad.minX + dx, sy, pad.width, 1.1));
          sy += 4.0;
        }
        gSlice.fill(scanPath, Shading.color(new RGBA(0, 0, 0, 0.24 * intensity)));
      }
    }
  }

  // --- Stage 2-4: Crisp macroblock codec corruption & pixel-sort streaks (hard digital cut, no mushy fade) ---
  if (t > 0.05 && t < 0.87) {
    const blockProgress = easeOut(phase(t, 0.05, 0.35)) * (1 - easeIn(phase(t, 0.62, 0.87)));
    const blockCount = Math.floor(lerp(2, 24, blockProgress));
    const activeTop = f.floating ? lerp(pad.minY, sinkY - 20, collapse * 0.88) : pad.minY;
    const activeBot = lerp(pad.maxY, sinkY + 20, collapse * 0.88);
    const activeH = Math.max(10, activeBot - activeTop);
    const sizeScale = lerp(1.0, 0.45, phase(t, 0.66, 0.87));

    for (let b = 0; b < blockCount; b++) {
      const seedK = burstStep * 31 + b;
      const rx = closeHash(b, seedK + 1, f.seed);
      const ry = closeHash(b, seedK + 2, f.seed);
      const rw = closeHash(b, seedK + 3, f.seed);
      const rh = closeHash(b, seedK + 4, f.seed);
      const kindRoll = closeHash(b, seedK + 5, f.seed);

      // Snap macroblocks to an 8pt digital codec grid.
      const bw = Math.max(8, Math.floor((lerp(16, 68, rw) * sizeScale) / 8) * 8);
      const bh = Math.max(4, Math.floor((lerp(6, 20, rh) * sizeScale) / 4) * 4);
      const bx = pad.minX - 24 + Math.floor((rx * (pad.width + 48 - bw)) / 8) * 8;
      const by = activeTop + Math.floor((ry * Math.max(4, activeH - bh)) / 4) * 4;

      if (!f.floating && by < pad.minY) continue;

      let col;
      if (kindRoll < 0.42) {
        const cCol = Math.min(f.cells.cols - 1, Math.max(0, Math.floor(rx * f.cells.cols)));
        const cRow = Math.min(f.cells.rows - 1, Math.max(0, Math.floor(ry * f.cells.rows)));
        const sampled = f.cells.color(cCol, cRow);
        col = sampled.a > 0.1 ? sampled.alpha(0.94) : f.bg.alpha(0.92);
      } else if (kindRoll < 0.62) {
        col = cyanCol.alpha(0.92);
      } else if (kindRoll < 0.80) {
        col = magCol.alpha(0.92);
      } else if (kindRoll < 0.91) {
        col = darkCut.alpha(0.95);
      } else {
        col = f.accent.mix(RGBA.white, 0.35).alpha(0.94);
      }

      ctx.fill(Path.rect(new CGRect(bx, by, bw, bh)), Shading.color(col));

      // Offset chromatic ghost bar on fault blocks.
      if (kindRoll >= 0.42 && kindRoll < 0.80) {
        const ghostCol = kindRoll < 0.62 ? magCol : cyanCol;
        const gShift = kindRoll < 0.62 ? -5 : 5;
        ctx.fill(Path.rect(new CGRect(bx + gShift, by + 2, bw * 0.65, Math.max(2, bh * 0.35))), Shading.color(ghostCol.alpha(0.78)));
      }
    }

    // Horizontal pixel-sort / tear streaks shooting out past the pad edges into the bleed area.
    const streakCount = Math.max(1, Math.floor(lerp(2, 7, blockProgress)));
    for (let s = 0; s < streakCount; s++) {
      const sy = activeTop + closeHash(s, step + 71, f.seed) * activeH;
      if (!f.floating && sy < pad.minY) continue;
      const sh = lerp(1.5, 3.8, closeHash(s, step + 73, f.seed));
      const sw = lerp(55, 200, closeHash(s, step + 79, f.seed)) * (1 - 0.40 * collapse);
      const sx = pad.minX - 48 + closeHash(s, step + 83, f.seed) * (pad.width + 96 - sw);
      const sKind = closeHash(s, step + 89, f.seed);
      let sCol;
      if (sKind < 0.36) {
        sCol = cyanCol.alpha(0.88);
      } else if (sKind < 0.68) {
        sCol = magCol.alpha(0.86);
      } else if (sKind < 0.86) {
        sCol = RGBA.white.alpha(0.90);
      } else {
        sCol = darkCut.alpha(0.90);
      }
      ctx.fill(Path.rect(new CGRect(sx, sy, sw, sh)), Shading.color(sCol));
    }
  }

  // --- Stage 5: Dead-signal snap-out at the sink (t = 0.74 -> 0.96, crisp digital cut) ---
  if (t >= 0.74 && t < 0.96) {
    const tailP = phase(t, 0.74, 0.96);
    // Hard staccato blink: snaps out cleanly on the last beat with zero mushy fade.
    const blinkOn = (t < 0.85) || (closeHash(step, 107, f.seed) > 0.25);
    if (blinkOn) {
      const tailW = lerp(pad.width * 0.72, 36, easeIn(tailP));
      const tailShift = (closeHash(step, 113, f.seed) - 0.5) * 40 * (1 - tailP);
      const lx = pad.midX - tailW * 0.5 + tailShift;
      const ly = f.floating ? sinkY : Math.max(pad.minY + 4, sinkY - 6 * tailP);

      // Dark contrast backing strip so the final snap reads crisply on white desktops.
      ctx.fill(Path.rect(new CGRect(lx - 4, ly - 2.5, tailW + 8, 5.5)), Shading.color(darkCut.alpha(0.55)));

      // Chromatic cyan + magenta offset signal tear lines.
      ctx.fill(Path.rect(new CGRect(lx - 7, ly - 1.5, tailW * 0.84, 2.0)), Shading.color(magCol.alpha(0.92)));
      ctx.fill(Path.rect(new CGRect(lx + 7, ly + 0.5, tailW * 0.84, 2.0)), Shading.color(cyanCol.alpha(0.94)));

      // Razor white core tear line.
      ctx.fill(Path.rect(new CGRect(lx, ly - 0.8, tailW, 1.8)), Shading.color(RGBA.white.alpha(0.96)));

      // Crisp snapping data flecks around the sink.
      const fleckCount = t < 0.88 ? 4 : 2;
      for (let k = 0; k < fleckCount; k++) {
        const fx = pad.midX + (closeHash(k, step + 127, f.seed) - 0.5) * tailW * 1.15;
        const fy = ly + (closeHash(k, step + 131, f.seed) - 0.5) * 18;
        if (!f.floating && fy < pad.minY) continue;
        const fw = lerp(8, 22, closeHash(k, step + 137, f.seed)) * (1 - 0.5 * tailP);
        const fh = lerp(2.5, 5.5, closeHash(k, step + 139, f.seed));
        const fCol = k === 0 ? cyanCol : (k === 1 ? magCol : (k === 2 ? darkCut : RGBA.white));
        ctx.fill(Path.rect(new CGRect(fx, fy, fw, fh)), Shading.color(fCol.alpha(0.94)));
      }
    }
  }
}
