// Burn closing animation: the pad catches fire at ignition spots along the bottom
// edge and burns upward like paper — toasted scorch, blackened char, incandescent
// ember rim, billowing flames, curling ash shreds, rising embers, and a smoke wisp.

export const kind = 'close';
export const duration = 1.0;

// Compute the ragged burn front Y coordinate for normalized x in [0, 1].
// At t = 0 the front sits safely below pad.maxY; it catches at two uneven pockets
// first, then eats upward across the pad and narrows into the sink.
function burnFrontY(u, t, pad, floating, seed) {
  const s1 = (seed + 17) >>> 0;
  const s2 = (seed + 53) >>> 0;
  const s3 = (seed + 97) >>> 0;

  // Two seeded ignition spots along the bottom edge (one primary, one secondary).
  const ig1 = 0.16 + closeHash(1, 3, s1) * 0.24; // left-ish
  const ig2 = 0.62 + closeHash(2, 5, s1) * 0.24; // right-ish

  const d1 = Math.abs(u - ig1);
  const d2 = Math.abs(u - ig2);

  // Strong semicircular bites early on so fire visibly catches at spots before spreading.
  const catch1 = smoothstep(0.0, 0.18, t);
  const catch2 = smoothstep(0.04, 0.24, t);
  const bite1 = Math.exp(-d1 * d1 * 11.0) * 0.30 * catch1;
  const bite2 = Math.exp(-d2 * d2 * 13.0) * 0.24 * catch2;

  // Main upward burn sweep: starts after ignition catches, accelerates cleanly.
  const sweepP = phase(t, 0.07, 0.84);
  const sweep = easeInOut(sweepP) * 0.62 + easeIn(sweepP) * 0.56;

  // Multi-octave organic paper-burn raggedness.
  const n1 = closeNoise(u * 4.8 + 0.7, t * 2.0, s1) - 0.5;
  const n2 = closeNoise(u * 11.5 + 3.9, t * 3.4, s2) - 0.5;
  const n3 = closeNoise(u * 25.0 + 8.3, t * 5.2, s3) - 0.5;
  const ragged = (n1 * 0.24 + n2 * 0.095 + n3 * 0.04) * smoothstep(0.0, 0.12, t);

  // Late-stage narrowing so the final charred tongue finishes into f.sink (the notch when docked).
  const edgeDist = Math.abs(u - 0.5) * 2.0;
  const sideBias = floating
    ? edgeDist * edgeDist * 0.14 * smoothstep(0.22, 0.78, sweepP)
    : edgeDist * edgeDist * 0.28 * smoothstep(0.24, 0.80, sweepP);

  // Dampen the early pocket bites once the main sweep dominates so the top finishes cleanly.
  const biteFade = 1.0 - smoothstep(0.55, 0.84, sweepP);
  const totalRise = sweep + (bite1 + bite2) * biteFade + sideBias + ragged;

  // Keep the non-ignited bottom edge intact briefly so the two ignition pockets visibly bite in first.
  const startOffset = 22.0 * (1.0 - smoothstep(0.0, 0.14, t));
  return pad.maxY + startOffset - totalRise * pad.height;
}

export function draw(f, ctx) {
  const t = f.t;
  if (t >= 1.0) return;

  if (t <= 0.0001) {
    f.drawPad(ctx);
    return;
  }

  const pad = f.pad;
  const padW = pad.width;
  const padH = pad.height;
  const seed = f.seed;

  // Sample the burn contour across the pad.
  const samples = 68;
  const xs = [];
  const ys = [];
  let maxFrontY = pad.minY - 60.0;
  let anyInsidePad = false;
  for (let i = 0; i <= samples; i++) {
    const u = i / samples;
    const x = pad.minX + u * padW;
    const y = burnFrontY(u, t, pad, f.floating, seed);
    xs.push(x);
    ys.push(y);
    if (y > maxFrontY) maxFrontY = y;
    if (y < pad.maxY + 2.0 && y > pad.minY - 4.0) anyInsidePad = true;
  }

  const padAlive = maxFrontY > pad.minY - 2.0;
  const burnActive = smoothstep(0.0, 0.05, t) * (1.0 - phase(t, 0.78, 0.88));

  // 1. Remaining unburned pad + contour-hugging scorch bands + blackened char rim.
  if (padAlive) {
    const remainPath = new Path();
    remainPath.move(new CGPoint(pad.minX - 2.0, pad.minY - 2.0));
    remainPath.addLine(new CGPoint(pad.maxX + 2.0, pad.minY - 2.0));
    remainPath.addLine(new CGPoint(xs[samples] + 2.0, ys[samples]));
    for (let i = samples; i >= 0; i--) {
      remainPath.addLine(new CGPoint(xs[i], ys[i]));
    }
    remainPath.closeSubpath();

    const gPad = ctx.copy();
    gPad.clip(f.padPath);
    gPad.clip(remainPath);
    f.drawPad(gPad);

    // 1b. Two contour-hugging scorch ribbons ahead of the burn line (works evenly on steep slopes).
    if (anyInsidePad) {
      const sSc = (seed + 211) >>> 0;
      const outerScorch = new Path();
      const innerScorch = new Path();
      for (let i = 0; i <= samples; i++) {
        const n = closeNoise(i * 0.24, t * 2.2, sSc);
        const hOut = 20.0 + n * 16.0;
        const hIn = 9.0 + n * 8.0;
        const pOut = new CGPoint(xs[i], ys[i] - hOut);
        const pIn = new CGPoint(xs[i], ys[i] - hIn);
        if (i === 0) {
          outerScorch.move(pOut);
          innerScorch.move(pIn);
        } else {
          outerScorch.addLine(pOut);
          innerScorch.addLine(pIn);
        }
      }
      for (let i = samples; i >= 0; i--) {
        outerScorch.addLine(new CGPoint(xs[i], ys[i] + 2.0));
        innerScorch.addLine(new CGPoint(xs[i], ys[i] + 2.0));
      }
      outerScorch.closeSubpath();
      innerScorch.closeSubpath();

      const outerCol = f.dark
        ? new RGBA(0.30, 0.08, 0.01, 0.26)
        : new RGBA(0.58, 0.36, 0.12, 0.28);
      const innerCol = f.dark
        ? new RGBA(0.42, 0.11, 0.02, 0.42)
        : new RGBA(0.32, 0.15, 0.04, 0.50);
      gPad.fill(outerScorch, Shading.color(outerCol));
      gPad.fill(innerScorch, Shading.color(innerCol));
    }

    // 1c. Blackened char rim right along the burning edge (clipped to padPath).
    if (anyInsidePad) {
      const charPath = new Path();
      const sChar = (seed + 307) >>> 0;
      const sDrop = (seed + 313) >>> 0;
      for (let i = 0; i <= samples; i++) {
        const thick = 5.0 + closeNoise(i * 0.42, t * 2.8, sChar) * 8.0;
        const pt = new CGPoint(xs[i], ys[i] - thick);
        if (i === 0) charPath.move(pt);
        else charPath.addLine(pt);
      }
      for (let i = samples; i >= 0; i--) {
        const droop = closeNoise(i * 0.55, t * 3.8, sDrop) * 4.0;
        charPath.addLine(new CGPoint(xs[i], ys[i] + droop));
      }
      charPath.closeSubpath();

      const gChar = ctx.copy();
      gChar.clip(f.padPath);
      gChar.fill(charPath, Shading.color(new RGBA(0.05, 0.035, 0.03, 0.96)));
    }
  }

  // 2. Delicate curling smoke wisps (single blurred layer, ribbon-shaped so they never read as grey dots).
  const smokeFade = phase(t, 0.05, 0.18) * (1.0 - easeIn(phase(t, 0.80, 1.0)));
  if (smokeFade > 0.01) {
    const gSmoke = ctx.copy();
    gSmoke.addFilter(Filter.blur(9.0));
    gSmoke.drawLayer((layer) => {
      const sSmoke = (seed + 409) >>> 0;
      const ribbonCount = 9;
      for (let i = 0; i < ribbonCount; i++) {
        const u = 0.14 + closeHash(i, 1, sSmoke) * 0.72;
        const startT = 0.04 + closeHash(i, 2, sSmoke) * 0.56;
        const lifeLen = 0.34 + closeHash(i, 3, sSmoke) * 0.24;
        const life = phase(t, startT, startT + lifeLen);
        if (life <= 0.0 || life >= 1.0) continue;

        const spawnY = burnFrontY(u, startT, pad, f.floating, seed);
        if (spawnY > pad.maxY + 2.0 || spawnY < pad.minY - 8.0) continue;

        const baseX = pad.minX + u * padW;
        const rise = easeOut(life) * (65.0 + closeHash(i, 4, sSmoke) * 70.0);
        const drift = (closeHash(i, 5, sSmoke) - 0.5) * 40.0 * life;
        const phaseOff = closeHash(i, 6, sSmoke) * 6.28;

        const rp = new Path();
        const segs = 6;
        const ribbonLen = 36.0 + life * 44.0;
        for (let k = 0; k <= segs; k++) {
          const frac = k / segs;
          const ry = spawnY - rise * 0.55 - frac * ribbonLen;
          const rx = baseX + drift * (0.4 + frac * 0.6) + Math.sin(life * 5.0 + frac * 3.4 + phaseOff) * (8.0 + frac * 12.0);
          const pt = new CGPoint(rx, ry);
          if (k === 0) rp.move(pt);
          else rp.addLine(pt);
        }

        const alpha = Math.sin(Math.PI * life) * 0.15 * smokeFade;
        const grey = f.dark ? 0.34 : 0.24;
        layer.stroke(
          rp,
          Shading.color(new RGBA(grey, grey * 0.96, grey * 0.93, alpha)),
          { lineWidth: lerp(8.0, 20.0, life), lineCap: 'round', lineJoin: 'round' }
        );
      }

      // Final graceful smoke wisp curling from the last burn point (t = 0.68..1.00).
      const wispLife = phase(t, 0.68, 1.0);
      if (wispLife > 0.0 && wispLife < 1.0) {
        const wispAlpha = Math.sin(Math.PI * wispLife) * 0.20;
        const ox = f.floating ? pad.midX : f.sink.midX;
        const oy = f.floating ? pad.minY + padH * 0.22 : f.sink.maxY + 28.0;
        const wp = new Path();
        for (let k = 0; k <= 7; k++) {
          const frac = k / 7.0;
          const wy = oy - frac * (55.0 + wispLife * 35.0) - wispLife * 18.0;
          const wx = ox + Math.sin(wispLife * 6.0 + frac * 3.8 + (seed % 5)) * (5.0 + frac * 14.0);
          const pt = new CGPoint(wx, wy);
          if (k === 0) wp.move(pt);
          else wp.addLine(pt);
        }
        layer.stroke(
          wp,
          Shading.color(new RGBA(0.30, 0.28, 0.27, wispAlpha)),
          { lineWidth: lerp(6.0, 15.0, wispLife), lineCap: 'round', lineJoin: 'round' }
        );
      }
    });
  }

  // 3. Incandescent glowing edge & organic billowing flames.
  if (padAlive && anyInsidePad && burnActive > 0.01) {
    // Active contour segments strictly inside the pad.
    const glowLine = new Path();
    let penDown = false;
    for (let i = 0; i <= samples; i++) {
      const y = ys[i];
      if (y <= pad.maxY + 1.0 && y >= pad.minY - 4.0) {
        const pt = new CGPoint(xs[i], Math.max(pad.minY, Math.min(pad.maxY, y)));
        if (!penDown) {
          glowLine.move(pt);
          penDown = true;
        } else {
          glowLine.addLine(pt);
        }
      } else {
        penDown = false;
      }
    }

    // Precompute varied organic flame tongues (broad, billowing, unevenly clustered).
    const sFlame = (seed + 521) >>> 0;
    const sSway = (seed + 547) >>> 0;
    const flameCount = 12;
    const flames = [];
    for (let i = 0; i < flameCount; i++) {
      const u = 0.06 + ((i + 0.5 + (closeHash(i, 1, sFlame) - 0.5) * 0.75) / flameCount) * 0.88;
      const idx = Math.max(0, Math.min(samples, Math.round(u * samples)));
      const fy = ys[idx];
      if (fy > pad.maxY + 0.5 || fy < pad.minY - 2.0) continue;

      const activity = closeNoise(i * 1.63, t * 11.0, sFlame);
      // Let some pockets smoulder without a tall flame so it looks irregular & natural.
      if (activity < 0.22) continue;

      const sizeBias = 0.65 + closeHash(i, 2, sFlame) * 0.85;
      const edgeFade = smoothstep(0.02, 0.12, u) * smoothstep(0.98, 0.88, u);
      const h = (16.0 + activity * 36.0) * sizeBias * burnActive * (0.5 + 0.5 * edgeFade);
      const w = (10.0 + closeHash(i, 3, sFlame) * 12.0) * (0.65 + 0.45 * activity);
      const sway = (closeNoise(i * 2.3, t * 9.5, sSway) - 0.5) * 20.0;
      const curl = (closeNoise(i * 3.1, t * 12.0, sSway) - 0.5) * 14.0;
      flames.push({ fx: xs[idx], fy, h, w, sway, curl, activity });
    }

    // 3a. Soft fire bloom + outer flame glow in ONE blurred layer.
    const gFireGlow = ctx.copy();
    gFireGlow.addFilter(Filter.blur(8.0));
    gFireGlow.drawLayer((layer) => {
      layer.stroke(
        glowLine,
        Shading.color(new RGBA(1.0, 0.28, 0.02, 0.92 * burnActive)),
        { lineWidth: 12.0, lineCap: 'round', lineJoin: 'round' }
      );

      for (let i = 0; i < flames.length; i++) {
        const fl = flames[i];
        const fp = new Path();
        fp.move(new CGPoint(fl.fx - fl.w * 0.62, fl.fy + 3.0));
        fp.addCurve(
          new CGPoint(fl.fx + fl.sway, fl.fy - fl.h * 1.08),
          new CGPoint(fl.fx - fl.w * 0.90, fl.fy - fl.h * 0.35),
          new CGPoint(fl.fx - fl.w * 0.25 + fl.curl, fl.fy - fl.h * 0.78)
        );
        fp.addCurve(
          new CGPoint(fl.fx + fl.w * 0.62, fl.fy + 3.0),
          new CGPoint(fl.fx + fl.w * 0.30 + fl.curl, fl.fy - fl.h * 0.75),
          new CGPoint(fl.fx + fl.w * 0.90, fl.fy - fl.h * 0.35)
        );
        fp.closeSubpath();
        layer.fill(fp, Shading.color(new RGBA(1.0, 0.34, 0.03, 0.72 * burnActive)));
      }
    });

    // 3b. Layered organic flames (rich amber-orange body + white-yellow inner core).
    for (let i = 0; i < flames.length; i++) {
      const fl = flames[i];
      const fp = new Path();
      fp.move(new CGPoint(fl.fx - fl.w * 0.54, fl.fy + 2.0));
      fp.addCurve(
        new CGPoint(fl.fx + fl.sway, fl.fy - fl.h),
        new CGPoint(fl.fx - fl.w * 0.78, fl.fy - fl.h * 0.34),
        new CGPoint(fl.fx - fl.w * 0.18 + fl.curl, fl.fy - fl.h * 0.72)
      );
      fp.addCurve(
        new CGPoint(fl.fx + fl.w * 0.54, fl.fy + 2.0),
        new CGPoint(fl.fx + fl.w * 0.22 + fl.curl, fl.fy - fl.h * 0.70),
        new CGPoint(fl.fx + fl.w * 0.78, fl.fy - fl.h * 0.34)
      );
      fp.closeSubpath();

      ctx.fill(
        fp,
        Shading.linearGradient(
          Gradient.stops([
            [new RGBA(1.0, 0.88, 0.36, 0.92 * burnActive), 0.0],
            [new RGBA(1.0, 0.44, 0.05, 0.80 * burnActive), 0.55],
            [new RGBA(0.88, 0.15, 0.01, 0.0), 1.0],
          ]),
          new CGPoint(fl.fx, fl.fy + 2.0),
          new CGPoint(fl.fx + fl.sway, fl.fy - fl.h)
        )
      );

      // Bright yellow-white core inside active flames.
      if (fl.activity > 0.38) {
        const ch = fl.h * 0.54;
        const cw = fl.w * 0.44;
        const cp = new Path();
        cp.move(new CGPoint(fl.fx - cw * 0.5, fl.fy + 1.0));
        cp.addQuadCurve(
          new CGPoint(fl.fx + fl.sway * 0.45, fl.fy - ch),
          new CGPoint(fl.fx - cw * 0.65, fl.fy - ch * 0.48)
        );
        cp.addQuadCurve(
          new CGPoint(fl.fx + cw * 0.5, fl.fy + 1.0),
          new CGPoint(fl.fx + cw * 0.65 + fl.sway * 0.2, fl.fy - ch * 0.48)
        );
        cp.closeSubpath();
        ctx.fill(cp, Shading.color(new RGBA(1.0, 0.97, 0.76, 0.86 * burnActive)));
      }
    }

    // 3c. Crisp molten ember line right on the char boundary.
    const gEmberLine = ctx.copy();
    gEmberLine.clip(f.padPath);
    gEmberLine.stroke(
      glowLine,
      Shading.color(new RGBA(1.0, 0.46, 0.05, 0.96 * burnActive)),
      { lineWidth: 4.0, lineCap: 'round', lineJoin: 'round' }
    );
    const gHotLine = gEmberLine.copy();
    gHotLine.blendMode = 'plusLighter';
    gHotLine.stroke(
      glowLine,
      Shading.color(new RGBA(1.0, 0.94, 0.58, 0.88 * burnActive)),
      { lineWidth: 1.7, lineCap: 'round', lineJoin: 'round' }
    );
  }

  // 4. Charred ash flakes & curling shreds peeling off behind the burn front.
  const sAsh = (seed + 619) >>> 0;
  const ashCount = 46;
  for (let i = 0; i < ashCount; i++) {
    const u = 0.04 + closeHash(i, 1, sAsh) * 0.92;
    const v = 0.05 + closeHash(i, 2, sAsh) * 0.90;
    const cellX = pad.minX + u * padW;
    const cellY = pad.minY + v * padH;

    const igniteT = lerp(0.05, 0.76, 1.0 - v) + (closeHash(i, 3, sAsh) - 0.5) * 0.08;
    const life = phase(t, igniteT, igniteT + 0.28);
    if (life <= 0.0 || life >= 1.0) continue;

    const curFront = burnFrontY(u, t, pad, f.floating, seed);
    if (curFront > cellY + 3.0) continue;

    const col = Math.max(0, Math.min(f.cells.cols - 1, Math.floor(u * f.cells.cols)));
    const row = Math.max(0, Math.min(f.cells.rows - 1, Math.floor(v * f.cells.rows)));
    const cellColor = f.cells.color(col, row);
    if (cellColor.a <= 0.05) continue;

    const ashBase = cellColor.mix(new RGBA(0.06, 0.045, 0.04, 1.0), 0.85);
    const flutter = Math.sin(life * 8.5 + i * 2.1) * 11.0 * life;
    const driftX = (closeHash(i, 4, sAsh) - 0.5) * 34.0 * life + flutter;
    const driftY = -16.0 * Math.sin(Math.PI * Math.min(1.0, life * 1.3)) + 28.0 * life * life;
    const px = cellX + driftX;
    const py = cellY + driftY;

    // A few bigger shreds among smaller flakes.
    const big = closeHash(i, 8, sAsh) > 0.78 ? 1.55 : 1.0;
    const size = (3.4 + closeHash(i, 5, sAsh) * 5.2) * big * (1.0 - 0.40 * life);
    const rot = (closeHash(i, 6, sAsh) - 0.5) * 3.0 + life * (closeHash(i, 7, sAsh) > 0.5 ? 2.8 : -2.8);
    const alpha = (1.0 - easeIn(life)) * 0.92;

    const gFlake = ctx.copy();
    gFlake.translateBy(px, py);
    gFlake.rotate(rot);
    const fp = new Path();
    fp.move(new CGPoint(-size * 0.65, -size * 0.35));
    fp.addLine(new CGPoint(size * 0.55, -size * 0.45));
    fp.addLine(new CGPoint(size * 0.68, size * 0.32));
    fp.addLine(new CGPoint(-size * 0.42, size * 0.48));
    fp.closeSubpath();
    gFlake.fill(fp, Shading.color(ashBase.alpha(alpha)));

    if (life < 0.42) {
      const emberAlpha = (1.0 - life / 0.42) * 0.90;
      gFlake.stroke(fp, Shading.color(new RGBA(1.0, 0.44, 0.05, emberAlpha)), 1.1);
    }
  }

  // 5. Rising glowing embers & sparks (abundant during the burn + deliberate glowing finish through t=0.98).
  // Brief warm afterglow at the final burn zone right as the last paper consumes.
  const lipGlow = Math.sin(Math.PI * phase(t, 0.72, 0.88));
  if (lipGlow > 0.01) {
    const gx = f.floating ? pad.midX : f.sink.midX;
    const gy = f.floating ? pad.minY + padH * 0.14 : f.sink.maxY - 2.0;
    const gw = f.floating ? 120.0 : f.sink.width * 0.75;
    const gh = 22.0;
    const gLip = ctx.copy();
    gLip.addFilter(Filter.blur(8.0));
    gLip.fill(
      Path.ellipse(new CGRect(gx - gw * 0.5, gy - gh * 0.5, gw, gh)),
      Shading.color(new RGBA(1.0, 0.36, 0.04, 0.42 * lipGlow))
    );
  }

  const sEmb = (seed + 733) >>> 0;
  const emberCount = 115;
  const hotEmberPath = new Path();
  const warmEmberPath = new Path();
  const coolEmberPath = new Path();

  for (let i = 0; i < emberCount; i++) {
    // Last 25 embers are late-finish sparks emitted as the final tongue consumes near the sink.
    const isLate = i >= emberCount - 25;
    const spread = (closeHash(i, 1, sEmb) + closeHash(i, 11, sEmb)) * 0.5;
    const u = isLate
      ? 0.22 + spread * 0.56
      : 0.05 + closeHash(i, 1, sEmb) * 0.90;
    const spawnT = isLate
      ? 0.68 + closeHash(i, 2, sEmb) * 0.14
      : 0.02 + closeHash(i, 2, sEmb) * 0.72;
    const lifeLen = isLate
      ? 0.16 + closeHash(i, 3, sEmb) * 0.16
      : 0.22 + closeHash(i, 3, sEmb) * 0.24;
    const life = phase(t, spawnT, spawnT + lifeLen);
    if (life <= 0.0 || life >= 1.0) continue;

    let startY = burnFrontY(u, spawnT, pad, f.floating, seed);
    if (isLate) {
      // Spawn near the final burn zone (just below the notch when docked, or upper pad when floating).
      startY = f.floating
        ? pad.minY + padH * (0.14 + closeHash(i, 9, sEmb) * 0.22)
        : f.sink.maxY + 6.0 + closeHash(i, 9, sEmb) * 42.0;
    } else if (startY > pad.maxY + 2.0 || startY < pad.minY - 8.0) {
      continue;
    }

    const startX = pad.minX + u * padW;
    const speedY = isLate
      ? 24.0 + closeHash(i, 4, sEmb) * 52.0
      : 60.0 + closeHash(i, 4, sEmb) * 110.0;
    const swayAmp = 8.0 + closeHash(i, 5, sEmb) * 18.0;
    const swayFreq = 4.0 + closeHash(i, 6, sEmb) * 5.0;
    const windX = (closeHash(i, 7, sEmb) - 0.5) * (isLate ? 64.0 : 44.0);

    // Late embers drift slightly downward/outward or float lazily so they stay in frame below the notch!
    const vertDisp = (isLate && !f.floating)
      ? (closeHash(i, 10, sEmb) - 0.35) * 46.0 * easeOut(life)
      : -speedY * easeOut(life);

    const ex = startX + windX * easeOut(life) + Math.sin(life * swayFreq + i * 1.9) * swayAmp * life;
    const ey = startY + vertDisp;
    if (ey < 2.0) continue;

    const baseR = 1.1 + closeHash(i, 8, sEmb) * 2.4;
    const r = baseR * (1.0 - 0.50 * life);
    const streakH = r * (1.5 + (speedY / 115.0) * 1.1 * (1.0 - life));
    const emberRect = new CGRect(ex - r * 0.75, ey - streakH, r * 1.5, streakH * 2.0);

    const pulse = 0.65 + 0.35 * Math.sin(t * 38.0 + i * 3.1);
    const fade = (1.0 - easeIn(life)) * pulse;
    if (fade < 0.08) continue;

    if (life < 0.32) {
      hotEmberPath.addEllipse(emberRect);
    } else if (life < 0.68) {
      warmEmberPath.addEllipse(emberRect);
    } else {
      coolEmberPath.addEllipse(emberRect);
    }
  }

  // Ember glow halo (2 fills in a single blurred context).
  const gEmbGlow = ctx.copy();
  gEmbGlow.addFilter(Filter.blur(3.5));
  gEmbGlow.fill(hotEmberPath, Shading.color(new RGBA(1.0, 0.55, 0.08, 0.88)));
  gEmbGlow.fill(warmEmberPath, Shading.color(new RGBA(1.0, 0.28, 0.02, 0.68)));

  // Crisp ember cores (visible on both dark and white backdrops).
  ctx.fill(coolEmberPath, Shading.color(new RGBA(0.82, 0.20, 0.02, 0.80)));
  ctx.fill(warmEmberPath, Shading.color(new RGBA(1.0, 0.52, 0.08, 0.96)));
  ctx.fill(hotEmberPath, Shading.color(new RGBA(1.0, 0.96, 0.74, 1.0)));
}
