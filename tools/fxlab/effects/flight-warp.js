export const kind = 'flight';
export const duration = 0.95;

// Warp jump boomerang animation:
// 1. Charge & recoil (0.00-0.14): floating pad coils slightly opposite travel while its leading edge ignites.
// 2. Leading-edge stretch (0.08-0.50): the pad stretches dramatically along its exact flight vector (leading edge
//    first, pinching transversely into a blazing warp streak) with forward light echoes, a leading bow-wave,
//    and pad-coloured slipstream streaks racing on top and around it.
// 3. Hyper-snap & arrival flash (0.44-0.82): the warp streak snaps cleanly into the notch inside a bright
//    anamorphic flash and a crisp, expanding shock ring.
// 4. Elastic spring-back (0.48-0.96): the docked pad bursts out of the flash anchored at the notch, overshoots
//    elastically, and settles cleanly into exact f.to with a brief energy sheen.

function warpTaperedStreak(p, x0, y0, x1, y1, wHead, wTail) {
  const dx = x1 - x0;
  const dy = y1 - y0;
  const len = Math.hypot(dx, dy);
  if (len < 0.5) return;
  const nx = -dy / len;
  const ny = dx / len;
  const sx = x0 + dx * 0.80;
  const sy = y0 + dy * 0.80;
  p.move(new CGPoint(x0 + nx * wTail, y0 + ny * wTail));
  p.addLine(new CGPoint(sx + nx * wHead, sy + ny * wHead));
  p.addLine(new CGPoint(x1, y1));
  p.addLine(new CGPoint(sx - nx * wHead, sy - ny * wHead));
  p.addLine(new CGPoint(x0 - nx * wTail, y0 - ny * wTail));
  p.closeSubpath();
}

function warpDiamondFlare(p, cx, cy, rx, ry) {
  if (rx <= 0.2 || ry <= 0.2) return;
  p.move(new CGPoint(cx - rx, cy));
  p.addQuadCurve(new CGPoint(cx, cy - ry), new CGPoint(cx - rx * 0.14, cy - ry * 0.14));
  p.addQuadCurve(new CGPoint(cx + rx, cy), new CGPoint(cx + rx * 0.14, cy - ry * 0.14));
  p.addQuadCurve(new CGPoint(cx, cy + ry), new CGPoint(cx + rx * 0.14, cy + ry * 0.14));
  p.addQuadCurve(new CGPoint(cx - rx, cy), new CGPoint(cx - rx * 0.14, cy + ry * 0.14));
  p.closeSubpath();
}

function drawDirectionalPad(f, ctx, cx, cy, theta, stretchX, pinchY, opacity, leadGlow, warpBlue, warpCyan, warpCore) {
  if (opacity <= 0.002) return;
  const g = ctx.copy();
  g.translateBy(cx, cy);
  g.rotate(theta);
  g.scaleBy(stretchX, pinchY);
  g.rotate(-theta);
  g.translateBy(-f.from.midX, -f.from.midY);
  g.clip(f.fromPath);
  f.drawFrom(g, f.from, opacity);

  // Directional leading-edge energy wash: trailing edge stays true to the pad, leading edge burns bright.
  if (leadGlow > 0.01) {
    const ux = Math.cos(theta);
    const uy = Math.sin(theta);
    const halfSpan = Math.hypot(f.from.width, f.from.height) * 0.52;
    const p0 = new CGPoint(f.from.midX - ux * halfSpan, f.from.midY - uy * halfSpan);
    const p1 = new CGPoint(f.from.midX + ux * halfSpan, f.from.midY + uy * halfSpan);
    const wg = g.copy();
    wg.blendMode = f.dark ? 'plusLighter' : 'normal';
    wg.fill(
      f.fromPath,
      Shading.linearGradient(
        Gradient.stops([
          [warpBlue.alpha(0.0), 0.0],
          [warpBlue.alpha((f.dark ? 0.25 : 0.14) * leadGlow), 0.45],
          [warpCyan.alpha((f.dark ? 0.65 : 0.34) * leadGlow), 0.82],
          [warpCore.alpha((f.dark ? 0.90 : 0.55) * leadGlow), 1.0],
        ]),
        p0,
        p1
      )
    );
  }
}

export function draw(f, ctx) {
  const fromCx = f.from.midX;
  const fromCy = f.from.midY;
  const toCx = f.to.midX;
  const toCy = f.to.midY;
  const dx = toCx - fromCx;
  const dy = toCy - fromCy;
  const dist = Math.max(1.0, Math.hypot(dx, dy));
  const ux = dx / dist;
  const uy = dy / dist;
  const vx = -uy;
  const vy = ux;
  const theta = Math.atan2(dy, dx);

  // Iconic warp cyan-blue tinted with theme accent + cobalt backing for crispness on white desktops.
  const warpBlue = new RGBA(0.22, 0.66, 1.0, 1.0).mix(f.accent, 0.26);
  const warpCobalt = new RGBA(0.10, 0.34, 0.78, 1.0).mix(f.accent, 0.22);
  const warpCyan = new RGBA(0.56, 0.92, 1.0, 1.0).mix(f.accent, 0.14);
  const warpCore = new RGBA(0.96, 0.99, 1.0, 1.0);
  const warpDeep = f.dark ? new RGBA(0.05, 0.14, 0.36, 1.0) : warpCobalt;

  const projLen = Math.max(180, Math.abs(f.from.width * ux) + Math.abs(f.from.height * uy));
  const projWidth = Math.max(160, Math.abs(f.from.width * vx) + Math.abs(f.from.height * vy));

  // Leading-edge-first kinematics: snappy anticipation recoil, rapid leading-edge stretch, clean snap at t=0.50.
  const recoil = Math.sin(Math.PI * phase(f.t, 0.0, 0.14)) * Math.min(22, dist * 0.065);
  const leadP = easeInOut(phase(f.t, 0.06, 0.48));
  const tailP = easeIn(phase(f.t, 0.18, 0.53));
  const midP = (leadP + tailP) * 0.5;
  const gap = Math.max(0, leadP - tailP);

  // --- Stage 1 & 2: Luminous warp corridor ribbon (behind the stretching pad) ---
  const bridge = Math.sin(Math.PI * phase(f.t, 0.18, 0.64));
  if (bridge > 0.01) {
    const bHeadP = clamp01(leadP * 1.04);
    const bTailP = clamp01(tailP * 0.85);
    const bx0 = fromCx + dx * bTailP;
    const by0 = fromCy + dy * bTailP;
    const bx1 = fromCx + dx * bHeadP;
    const by1 = fromCy + dy * bHeadP;
    const ribbonW = projWidth * lerp(0.14, 0.30, bridge) * (1 - smoothstep(0.46, 0.64, f.t) * 0.65);

    const rb = new Path();
    warpTaperedStreak(rb, bx0, by0, bx1, by1, ribbonW * 0.52, ribbonW * 0.10);
    const rg = ctx.copy();
    rg.blendMode = f.dark ? 'plusLighter' : 'normal';
    rg.fill(
      rb,
      Shading.linearGradient(
        Gradient.stops([
          [warpBlue.alpha(0.0), 0.0],
          [warpBlue.alpha((f.dark ? 0.38 : 0.24) * bridge), 0.45],
          [warpCyan.alpha((f.dark ? 0.68 : 0.42) * bridge), 0.88],
          [warpCore.alpha((f.dark ? 0.82 : 0.52) * bridge), 1.0],
        ]),
        new CGPoint(bx0, by0),
        new CGPoint(bx1, by1)
      )
    );
  }

  // --- Stage 2: The floating pad stretching into a sleek warp streak (cleanly finishes by t=0.51) ---
  const fromFade = 1 - smoothstep(0.42, 0.51, f.t);
  if (fromFade > 0.002) {
    // Sleek dramatic elongation + transverse pinch so it truly reads as a light-speed streak, not a slab.
    const streakRamp = easeIn(phase(f.t, 0.12, 0.50));
    const stretch = Math.min(4.0, 1.0 + (gap * dist * 1.55) / projLen + streakRamp * 0.85);
    const pinch = Math.max(0.24, 1.0 / Math.pow(stretch, 0.62) * (1.0 - streakRamp * 0.35));
    const curCx = fromCx + dx * midP - ux * recoil;
    const curCy = fromCy + dy * midP - uy * recoil;

    // Luminous trailing echoes behind the stretching pad (ramp in smoothly once stretch begins).
    const echoStrength = Math.sin(Math.PI * phase(f.t, 0.12, 0.51));
    const echoRamp = smoothstep(0.12, 0.28, f.t);
    const leadGlow = smoothstep(0.04, 0.44, f.t);
    if (echoStrength > 0.01 && echoRamp > 0.01) {
      for (let k = 4; k >= 1; k--) {
        const lagP = clamp01(midP - k * 0.045 * echoRamp);
        const eStretch = Math.min(4.2, stretch * (1.0 + k * 0.08 * echoRamp));
        const ePinch = Math.max(0.18, pinch * (1.0 - k * 0.05 * echoRamp));
        const ex = fromCx + dx * lagP - ux * recoil;
        const ey = fromCy + dy * lagP - uy * recoil;
        const eOp = (0.24 / k) * echoStrength * fromFade;
        drawDirectionalPad(f, ctx, ex, ey, theta, eStretch, ePinch, eOp, leadGlow * 0.95, warpBlue, warpCyan, warpCore);
      }
    }

    // Main stretching pad with directional leading-edge light wash.
    drawDirectionalPad(f, ctx, curCx, curCy, theta, stretch, pinch, fromFade, leadGlow, warpBlue, warpCyan, warpCore);

    // Crisp warp-field outline fading out smoothly as the pad becomes pure light.
    const rim = Math.sin(Math.PI * phase(f.t, 0.0, 0.48));
    if (rim > 0.01) {
      const rg = ctx.copy();
      rg.translateBy(curCx, curCy);
      rg.rotate(theta);
      rg.scaleBy(stretch, pinch);
      rg.rotate(-theta);
      rg.translateBy(-f.from.midX, -f.from.midY);
      rg.stroke(f.fromPath, Shading.color(warpDeep.alpha((f.dark ? 0.24 : 0.40) * rim)), 2.8);
      const rg2 = rg.copy();
      rg2.blendMode = 'plusLighter';
      rg2.stroke(f.fromPath, Shading.color(warpCyan.alpha(0.88 * rim)), 1.5);
    }

    // Bright leading-edge warp lance right at the nose of the stretching pad.
    const noseGlow = Math.sin(Math.PI * phase(f.t, 0.10, 0.52));
    if (noseGlow > 0.01) {
      const noseDist = projLen * 0.48 * stretch;
      const nx = curCx + ux * Math.min(noseDist, dist * 0.55);
      const ny = curCy + uy * Math.min(noseDist, dist * 0.55);
      const tx = curCx - ux * Math.min(noseDist * 0.65, dist * 0.40);
      const ty = curCy - uy * Math.min(noseDist * 0.65, dist * 0.40);
      const lance = new Path();
      warpTaperedStreak(lance, tx, ty, nx, ny, lerp(4, 14, noseGlow), 1.0);
      const lg = ctx.copy();
      lg.blendMode = 'plusLighter';
      lg.fill(lance, Shading.color(warpCore.alpha(0.75 * noseGlow)));
    }
  }

  // --- Stage 5: Docked pad emerging from the arrival flash with elastic spring-back ---
  const toAppear = smoothstep(0.47, 0.54, f.t);
  if (toAppear > 0.002) {
    const settleT = phase(f.t, 0.48, 0.94);
    const spring = settleT < 1 ? Math.exp(-6.2 * settleT) * Math.cos(Math.PI * 2.5 * settleT) : 0;
    const dampEnv = 1 - smoothstep(0.82, 0.94, f.t);
    const osc = spring * dampEnv;

    // Anchor at the notch so the docked pad slams into place and springs smoothly without clipping above y=0.
    const anchorX = toCx;
    const anchorY = f.to.minY + 12;
    const scaleX = 1.0 - 0.15 * osc;
    const scaleY = 1.0 + 0.20 * osc;
    const shiftX = -ux * 24 * Math.max(0, osc);
    const shiftY = -uy * 16 * Math.max(0, osc);

    const tg = ctx.copy();
    tg.translateBy(anchorX + shiftX, anchorY + shiftY);
    tg.scaleBy(scaleX, scaleY);
    tg.translateBy(-anchorX, -anchorY);
    tg.clip(f.toPath);
    f.drawTo(tg, f.to, toAppear);

    // Brief luminous energy sheen sweeping down the docked pad as it locks in.
    const sheenT = phase(f.t, 0.50, 0.80);
    if (sheenT > 0 && sheenT < 1) {
      const sheenAlpha = Math.sin(Math.PI * sheenT) * 0.42;
      const sg = tg.copy();
      sg.blendMode = f.dark ? 'plusLighter' : 'normal';
      const sweepY = lerp(f.to.minY - 60, f.to.maxY + 60, easeOut(sheenT));
      sg.fill(
        f.toPath,
        Shading.linearGradient(
          Gradient.stops([
            [warpCyan.alpha(0.0), 0.0],
            [warpCyan.alpha(sheenAlpha), 0.48],
            [warpCore.alpha(sheenAlpha * 0.85), 0.54],
            [warpCyan.alpha(0.0), 1.0],
          ]),
          new CGPoint(toCx, sweepY - 50),
          new CGPoint(toCx, sweepY + 50)
        )
      );
    }

    const toRim = Math.sin(Math.PI * phase(f.t, 0.48, 0.76));
    if (toRim > 0.01) {
      const rg = ctx.copy();
      rg.translateBy(anchorX + shiftX, anchorY + shiftY);
      rg.scaleBy(scaleX, scaleY);
      rg.translateBy(-anchorX, -anchorY);
      rg.blendMode = f.dark ? 'plusLighter' : 'normal';
      rg.stroke(f.toPath, Shading.color(warpCyan.alpha(0.75 * toRim)), 1.8);
    }
  }

  // --- Pad-coloured slipstream streaks & high-speed corridor lines (drawn OVER the pad so they blaze vividly) ---
  const wakePresence = Math.sin(Math.PI * phase(f.t, 0.03, 0.74));
  if (wakePresence > 0.01) {
    const cellBack = new Path();
    const cellCore = new Path();
    const cellStreaks = [];
    const step = 4;

    for (let row = 0; row < f.fromCells.rows; row += step) {
      for (let col = 0; col < f.fromCells.cols; col += step) {
        const c = f.fromCells.color(col, row);
        if (c.a <= 0.05) continue;

        const h0 = closeHash(col, row, f.seed);
        const h1 = closeHash(col, row, (f.seed + 29) >>> 0);
        const h2 = closeHash(col, row, (f.seed + 71) >>> 0);

        const contrast =
          Math.abs(c.r - f.bg.r) + Math.abs(c.g - f.bg.g) + Math.abs(c.b - f.bg.b);
        const isText = contrast > 0.20;
        if (!isText && h2 < 0.48) continue;

        const cell = f.fromCells.rect(col, row);
        const relX = cell.midX - fromCx;
        const relY = cell.midY - fromCy;

        const along = relX * ux + relY * uy;
        const across = relX * vx + relY * vy;
        const leadBias = clamp01(0.5 - along / projLen);

        const start = lerp(0.03, 0.20, h0) + leadBias * 0.07;
        const dur = lerp(0.36, 0.48, h1);
        const u = phase(f.t, start, start + dur);
        if (u <= 0 || u >= 1) continue;

        const headU = easeInOut(clamp01(u * 1.22));
        const tailU = easeIn(phase(u, 0.16, 1.0));

        const pinchLane = 1.0 - 0.50 * Math.sin(Math.PI * u);
        const latX = vx * across * pinchLane;
        const latY = vy * across * pinchLane;
        const alongOffset = along * (1.0 - 0.60 * Math.sin(Math.PI * u));

        const x1 = fromCx + dx * headU + latX + ux * alongOffset;
        const y1 = fromCy + dy * headU + latY + uy * alongOffset;
        const x0 = fromCx + dx * tailU + latX + ux * alongOffset;
        const y0 = fromCy + dy * tailU + latY + uy * alongOffset;

        const fade = Math.sin(Math.PI * u);
        const isHero = isText || h2 > 0.76;
        const w = (isHero ? lerp(1.3, 2.5, h2) : lerp(0.8, 1.4, h2)) * (0.45 + 0.55 * fade);

        const shift = smoothstep(0.12, 0.78, u);
        const targetHue = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.62);
        const colColor = c.mix(targetHue, shift * 0.74).mix(warpCore, f.dark ? shift * 0.42 : shift * 0.18);

        if (isHero) {
          warpTaperedStreak(cellBack, x0, y0, x1, y1, w * 1.35, w * 0.25);
          warpTaperedStreak(cellCore, x0 + (x1 - x0) * 0.32, y0 + (y1 - y0) * 0.32, x1, y1, w * 0.50, 0.14);
        }
        cellStreaks.push({ x0, y0, x1, y1, w, color: colColor.alpha(fade * (isHero ? 0.94 : 0.74)) });
      }
    }

    if (!cellBack.isEmpty) {
      ctx.fill(cellBack, Shading.color(warpDeep.alpha((f.dark ? 0.22 : 0.34) * wakePresence)));
    }
    for (let i = 0; i < cellStreaks.length; i++) {
      const s = cellStreaks[i];
      const sp = new Path();
      warpTaperedStreak(sp, s.x0, s.y0, s.x1, s.y1, s.w, s.w * 0.16);
      ctx.fill(sp, Shading.color(s.color));
    }
    if (!cellCore.isEmpty) {
      const cg = ctx.copy();
      cg.blendMode = 'plusLighter';
      cg.fill(cellCore, Shading.color(warpCore.alpha(0.86 * wakePresence)));
    }

    // Dedicated high-speed warp corridor lines flanking the flight path.
    const slipBack = new Path();
    const slipBlue = new Path();
    const slipCore = new Path();
    const slipCount = 44;

    for (let i = 0; i < slipCount; i++) {
      const h0 = closeHash(i, 401, f.seed);
      const h1 = closeHash(i, 503, f.seed);
      const h2 = closeHash(i, 607, f.seed);

      const start = lerp(0.05, 0.26, h0);
      const dur = lerp(0.34, 0.46, h1);
      const u = phase(f.t, start, start + dur);
      if (u <= 0 || u >= 1) continue;

      const lane = (h2 - 0.5) * projWidth * 1.18;
      const pinchLane = 1.0 - 0.42 * Math.sin(Math.PI * u);
      const headU = easeInOut(clamp01(u * 1.24));
      const tailU = easeIn(phase(u, 0.18, 1.0));
      const extraLead = lerp(-20, 55, h1);

      const x1 = fromCx + dx * headU + vx * lane * pinchLane + ux * extraLead;
      const y1 = fromCy + dy * headU + vy * lane * pinchLane + uy * extraLead;
      const x0 = fromCx + dx * tailU + vx * lane * pinchLane + ux * (extraLead - 48);
      const y0 = fromCy + dy * tailU + vy * lane * pinchLane + uy * (extraLead - 48);

      const w = lerp(0.95, 2.5, h1 * h1) * Math.sin(Math.PI * u);
      warpTaperedStreak(slipBack, x0, y0, x1, y1, w * 1.38, w * 0.24);
      warpTaperedStreak(slipBlue, x0, y0, x1, y1, w * 1.12, w * 0.18);
      warpTaperedStreak(slipCore, x0 + (x1 - x0) * 0.36, y0 + (y1 - y0) * 0.36, x1, y1, w * 0.54, 0.14);
    }

    if (!slipBack.isEmpty) {
      ctx.fill(slipBack, Shading.color(warpDeep.alpha((f.dark ? 0.22 : 0.36) * wakePresence)));
    }
    if (!slipBlue.isEmpty) {
      const bg = ctx.copy();
      bg.blendMode = f.dark ? 'plusLighter' : 'normal';
      const slipHue = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.66);
      bg.fill(slipBlue, Shading.color(slipHue.alpha(0.86 * wakePresence)));
    }
    if (!slipCore.isEmpty) {
      const cg = ctx.copy();
      cg.blendMode = 'plusLighter';
      cg.fill(slipCore, Shading.color(warpCore.alpha(0.92 * wakePresence)));
    }
  }

  // --- Stage 4: Arrival flash, crisp shock ring & anamorphic lens flare ---
  const impactX = toCx;
  const impactY = f.to.minY + f.to.height * 0.34;

  // Crisp, razor-clean expanding shock ring (thin leading energy rim so it never obscures the docked text).
  const ringT = phase(f.t, 0.48, 0.86);
  if (ringT > 0 && ringT < 1) {
    const ringEase = easeOut(ringT);
    const outerR = lerp(28, Math.max(f.to.width, f.to.height) * 0.78, ringEase);
    const innerStop = lerp(0.74, 0.90, ringT);
    const ringFade = Math.sin(Math.PI * ringT) * (1 - ringT * 0.40);

    const ringRect = new CGRect(impactX - outerR, impactY - outerR * 0.70, outerR * 2, outerR * 1.40);
    const wg = ctx.copy();
    wg.blendMode = f.dark ? 'plusLighter' : 'normal';
    wg.fill(
      Path.ellipse(ringRect),
      Shading.radialGradient(
        Gradient.stops([
          [warpBlue.alpha(0.0), 0.0],
          [warpBlue.alpha(0.0), innerStop],
          [warpCyan.alpha((f.dark ? 0.48 : 0.32) * ringFade), Math.min(0.96, innerStop + 0.07)],
          [warpCore.alpha((f.dark ? 0.85 : 0.52) * ringFade), 0.97],
          [warpBlue.alpha(0.0), 1.0],
        ]),
        new CGPoint(impactX, impactY),
        0,
        outerR
      )
    );
    if (!f.dark) {
      ctx.stroke(Path.ellipse(ringRect), Shading.color(warpCobalt.alpha(0.24 * ringFade)), 1.6);
    }
  }

  // Arrival flash envelope peaking right at the snap (t=0.51-0.54).
  const flashRise = easeOut(phase(f.t, 0.44, 0.53));
  const flashFall = 1 - easeOut(phase(f.t, 0.53, 0.80));
  const flash = flashRise * flashFall;

  // Single blurred bloom layer (1 blurred draw total per frame).
  if (flash > 0.01) {
    const bloomCtx = ctx.copy();
    bloomCtx.addFilter(Filter.blur(14));
    bloomCtx.drawLayer((layer) => {
      const darkR = lerp(22, 98, flash);
      layer.fill(
        Path.ellipse(new CGRect(impactX - darkR, impactY - darkR * 0.62, darkR * 2, darkR * 1.24)),
        Shading.color(warpDeep.alpha((f.dark ? 0.28 : 0.46) * flash))
      );
      const glowR = lerp(18, 90, flash);
      layer.fill(
        Path.ellipse(new CGRect(impactX - glowR, impactY - glowR * 0.62, glowR * 2, glowR * 1.24)),
        Shading.color(warpBlue.alpha(0.88 * flash))
      );
      const barW = lerp(45, 420, easeOut(flash));
      const barH = lerp(4, 15, flash);
      layer.fill(
        Path.ellipse(new CGRect(impactX - barW * 0.5, impactY - barH * 0.5, barW, barH)),
        Shading.color(warpCyan.alpha(0.84 * flash))
      );
    });

    // Crisp anamorphic lens flare across the arrival point.
    const flareW = lerp(28, 390, easeOut(flash));
    const flareH = lerp(2.5, 11.5, flash);
    const vertH = lerp(10, 74, flash);

    const flareBack = new Path();
    warpDiamondFlare(flareBack, impactX, impactY, flareW * 1.02, flareH * 1.36);
    ctx.fill(flareBack, Shading.color(warpDeep.alpha((f.dark ? 0.22 : 0.38) * flash)));

    const fg = ctx.copy();
    fg.blendMode = f.dark ? 'plusLighter' : 'normal';
    const horiz = new Path();
    warpDiamondFlare(horiz, impactX, impactY, flareW, flareH);
    fg.fill(horiz, Shading.color(warpCyan.alpha(0.92 * flash)));

    const vert = new Path();
    warpDiamondFlare(vert, impactX, impactY, flareH * 0.85, vertH);
    fg.fill(vert, Shading.color(warpCyan.alpha(0.76 * flash)));

    const cg = ctx.copy();
    cg.blendMode = 'plusLighter';
    const core = new Path();
    warpDiamondFlare(core, impactX, impactY, flareW * 0.60, flareH * 0.52);
    warpDiamondFlare(core, impactX, impactY, flareH * 0.45, vertH * 0.55);
    cg.fill(core, Shading.color(warpCore.alpha(0.98 * flash)));
  }
}
