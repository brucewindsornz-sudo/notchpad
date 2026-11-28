export const kind = 'close';
export const duration = 0.95;

// Hyperspace closing animation:
// 1. Ignition (0.00-0.16): vanishing point charges immediately; pad edges blueshift and text/UI cells ignite.
// 2. Radial stretch (0.04-0.52): the pad pulls and smears radially into the vanishing point while its own
//    pixels stretch into tapered star-lines (in their own colours shifting to electric blue-white) alongside
//    deep-field hyperspace tunnel rays.
// 3. Jump flash (0.44-0.76): converging streaks trigger an anamorphic lens flare, radial energy wave, and bloom.
// 4. Receding star (0.60-0.98): a crisp 4-point star glint lingers at the vanishing point and winks out cleanly.

function taperedStreak(p, x0, y0, x1, y1, wHead, wTail) {
  const dx = x1 - x0;
  const dy = y1 - y0;
  const len = Math.hypot(dx, dy);
  if (len < 0.5) return;
  const nx = -dy / len;
  const ny = dx / len;
  // Shoulder sits 80% of the way toward the leading head for a sleek needle profile.
  const sx = x0 + dx * 0.80;
  const sy = y0 + dy * 0.80;
  p.move(new CGPoint(x0 + nx * wTail, y0 + ny * wTail));
  p.addLine(new CGPoint(sx + nx * wHead, sy + ny * wHead));
  p.addLine(new CGPoint(x1, y1));
  p.addLine(new CGPoint(sx - nx * wHead, sy - ny * wHead));
  p.addLine(new CGPoint(x0 - nx * wTail, y0 - ny * wTail));
  p.closeSubpath();
}

function addDiamondFlare(p, cx, cy, rx, ry) {
  if (rx <= 0.2 || ry <= 0.2) return;
  p.move(new CGPoint(cx - rx, cy));
  p.addQuadCurve(new CGPoint(cx, cy - ry), new CGPoint(cx - rx * 0.13, cy - ry * 0.13));
  p.addQuadCurve(new CGPoint(cx + rx, cy), new CGPoint(cx + rx * 0.13, cy - ry * 0.13));
  p.addQuadCurve(new CGPoint(cx, cy + ry), new CGPoint(cx + rx * 0.13, cy + ry * 0.13));
  p.addQuadCurve(new CGPoint(cx - rx, cy), new CGPoint(cx - rx * 0.13, cy + ry * 0.13));
  p.closeSubpath();
}

export function draw(f, ctx) {
  const vpX = f.target.x;
  const vpY = f.target.y;
  const padW = f.pad.width;
  const padH = f.pad.height;
  const maxR = Math.hypot(padW, padH) * 0.80;

  // Iconic hyperspace palette tinted with theme accent, plus a rich cobalt-indigo backing
  // so light themes and white desktops keep luminous, colourful contrast (never muddy grey).
  const warpBlue = new RGBA(0.24, 0.66, 1.0, 1.0).mix(f.accent, 0.22);
  const warpCobalt = new RGBA(0.10, 0.34, 0.78, 1.0).mix(f.accent, 0.18);
  const warpCyan = new RGBA(0.56, 0.90, 1.0, 1.0).mix(f.accent, 0.12);
  const warpCore = new RGBA(0.96, 0.99, 1.0, 1.0);
  const warpDeep = f.dark ? new RGBA(0.05, 0.14, 0.36, 1.0) : warpCobalt;
  const backingStrength = f.dark ? 0.30 : 0.58;

  // --- Stage 1 & 2: The pad itself pulling and smearing into the vanishing point ---
  const pullRaw = phase(f.t, 0.0, 0.50);
  const pull = easeIn(pullRaw);
  const padAlpha = 1 - smoothstep(0.28, 0.47, f.t);

  if (padAlpha > 0.002) {
    // Radial motion-smear echoes pulling the pad's picture toward the vanishing point.
    const echoStrength = Math.sin(Math.PI * phase(f.t, 0.01, 0.48));
    if (echoStrength > 0.01) {
      for (let k = 5; k >= 1; k--) {
        // Echoes stretch slightly ahead toward the vanishing point to read as forward motion blur.
        const leadT = clamp01(pullRaw + k * 0.036);
        const lead = easeIn(leadT);
        const sx = lerp(1.0, 0.06, lead);
        const sy = lerp(1.0, f.floating ? 0.06 : 0.09, lead * 0.94);
        const ew = padW * sx;
        const eh = padH * sy;
        const ex = lerp(f.pad.midX, vpX, lead) - ew * 0.5;
        const ey = f.floating
          ? lerp(f.pad.midY, vpY, lead) - eh * 0.5
          : lerp(f.pad.minY, Math.max(0, vpY - eh * 0.35), lead);
        const er = new CGRect(ex, ey, ew, eh);
        const eOp = (0.24 / k) * echoStrength * padAlpha;

        const eg = ctx.copy();
        eg.clip(f.padPathIn(er));
        f.drawPad(eg, er, eOp);
        eg.fill(f.padPathIn(er), Shading.color(warpBlue.alpha(eOp * 0.55)));
      }
    }

    // Main pad shrinking and accelerating into the vanishing point.
    const sx = lerp(1.0, 0.05, pull);
    const sy = lerp(1.0, f.floating ? 0.05 : 0.08, pull * 0.94);
    const curW = padW * sx;
    const curH = padH * sy;
    const curX = lerp(f.pad.midX, vpX, pull) - curW * 0.5;
    const curY = f.floating
      ? lerp(f.pad.midY, vpY, pull) - curH * 0.5
      : lerp(f.pad.minY, Math.max(0, vpY - curH * 0.35), pull);
    const curRect = new CGRect(curX, curY, curW, curH);
    const curPath = f.padPathIn(curRect);

    const pg = ctx.copy();
    pg.clip(curPath);
    f.drawPad(pg, curRect, padAlpha);

    // Blue-shift radial wash creeping across the pad from frame 2 onward.
    const wash = smoothstep(0.02, 0.36, f.t) * padAlpha;
    if (wash > 0.01) {
      const wg = pg.copy();
      wg.blendMode = f.dark ? 'plusLighter' : 'normal';
      wg.fill(
        curPath,
        Shading.radialGradient(
          Gradient.stops([
            [warpBlue.alpha(0.0), 0.0],
            [warpBlue.alpha((f.dark ? 0.32 : 0.22) * wash), 0.58],
            [warpCyan.alpha((f.dark ? 0.72 : 0.45) * wash), 1.0],
          ]),
          new CGPoint(curRect.midX, f.floating ? curRect.midY : curRect.minY + curRect.height * 0.14),
          0,
          Math.max(curW, curH) * 0.72
        )
      );
    }

    // Softly glowing rim that ignites quickly and dissolves before the pad vanishes (no boxy residue).
    const rim = Math.sin(Math.PI * phase(f.t, 0.0, 0.38));
    if (rim > 0.01) {
      ctx.stroke(curPath, Shading.color(warpDeep.alpha(backingStrength * 0.55 * rim)), 2.8);
      const rg = ctx.copy();
      rg.blendMode = 'plusLighter';
      rg.stroke(curPath, Shading.color(warpCyan.alpha(0.75 * rim)), 1.4);
    }
  }

  // --- Early vanishing-point ignition glint (sharp singularity, gives instant read in first 150 ms) ---
  const charge = Math.sin(Math.PI * phase(f.t, 0.0, 0.44));
  if (charge > 0.01) {
    const cr = lerp(5, 24, charge);
    const cg = ctx.copy();
    cg.blendMode = f.dark ? 'plusLighter' : 'normal';
    cg.fill(
      Path.ellipse(new CGRect(vpX - cr, vpY - cr * 0.65, cr * 2, cr * 1.3)),
      Shading.radialGradient(
        Gradient.stops([
          [warpCore.alpha(0.75 * charge), 0.0],
          [warpBlue.alpha(0.38 * charge), 0.45],
          [warpBlue.alpha(0.0), 1.0],
        ]),
        new CGPoint(vpX, vpY),
        0,
        cr
      )
    );
    const spark = new Path();
    addDiamondFlare(spark, vpX, vpY, lerp(6, 46, charge), lerp(1.0, 2.8, charge));
    addDiamondFlare(spark, vpX, vpY, lerp(1.0, 2.2, charge), lerp(4, 18, charge));
    cg.fill(spark, Shading.color(warpCore.alpha(0.70 * charge)));
  }

  // --- Stage 2 & 3: Star-lines born from the pad's own cells ---
  // Pass A: collect geometry so backing is drawn UNDER coloured streaks, and white-hot cores ON TOP.
  const cellBackPath = new Path();
  const cellCorePath = new Path();
  const cellStep = 3;
  const streaks = [];

  for (let row = 0; row < f.cells.rows; row += cellStep) {
    for (let col = 0; col < f.cells.cols; col += cellStep) {
      const c = f.cells.color(col, row);
      if (c.a <= 0.05) continue;

      const h0 = closeHash(col, row, f.seed);
      const h1 = closeHash(col, row, (f.seed + 17) >>> 0);
      const h2 = closeHash(col, row, (f.seed + 53) >>> 0);

      // Text & UI cells stand out against the background and ignite slightly earlier.
      const contrast =
        Math.abs(c.r - f.bg.r) + Math.abs(c.g - f.bg.g) + Math.abs(c.b - f.bg.b);
      const isText = contrast > 0.20;
      if (!isText && h2 < 0.36) continue;

      const cell = f.cells.rect(col, row);
      const cx = cell.midX;
      const cy = cell.midY;
      const dx = cx - vpX;
      const dy = cy - vpY;
      const dist = Math.hypot(dx, dy);
      if (dist < 6) continue;

      const ux = dx / dist;
      const uy = dy / dist;
      const normDist = clamp01(dist / maxR);

      // Early ignition so star-lines are already unmistakably streaking by t = 0.08-0.13.
      const start = Math.max(0.005, lerp(0.005, 0.17, h0) + (1 - normDist) * 0.07 - (isText ? 0.025 : 0));
      const lifeDur = lerp(0.36, 0.52, h1);
      const u = phase(f.t, start, start + lifeDur);
      if (u <= 0 || u >= 1) continue;

      // Brief outward hyperspace stretch kick, then whip inward into the vanishing point.
      const kick = Math.sin(Math.PI * clamp01(u / 0.34)) * lerp(26, 92, h1) * (0.35 + 0.65 * normDist);
      const headProgress = easeIn(clamp01(u * 1.18));
      const tailProgress = easeIn(phase(u, 0.14, 1.0));

      const headR = Math.max(0, dist * (1 - headProgress));
      const tailR = Math.max(headR + 2.5, (dist + kick) * (1 - tailProgress));

      const x0 = vpX + ux * tailR;
      const y0 = vpY + uy * tailR;
      const x1 = vpX + ux * headR;
      const y1 = vpY + uy * headR;

      const fade = Math.sin(Math.PI * clamp01(u)) * (1 - smoothstep(0.64, 0.78, f.t));
      if (fade <= 0.01) continue;

      const isHero = isText || h2 > 0.74;
      const wHead = (isHero ? lerp(1.4, 2.8, h2) : lerp(0.8, 1.5, h2)) * (0.45 + 0.55 * fade);
      const wTail = wHead * 0.16;

      const blueShift = smoothstep(0.12, 0.76, u);
      const targetHue = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.55);
      const baseColor = c.mix(targetHue, blueShift * 0.76).mix(warpCore, f.dark ? blueShift * 0.36 : blueShift * 0.18);

      if (isHero) {
        taperedStreak(cellBackPath, x0, y0, x1, y1, wHead * 1.35, wTail * 1.25);
        taperedStreak(cellCorePath, x0 + (x1 - x0) * 0.30, y0 + (y1 - y0) * 0.30, x1, y1, wHead * 0.50, 0.15);
      }

      streaks.push({ x0, y0, x1, y1, wHead, wTail, color: baseColor.alpha(fade * (isHero ? 0.94 : 0.76)) });
    }
  }

  // Draw backing UNDERNEATH the coloured streaks so light themes stay crisp and luminous.
  const streakPresence = Math.sin(Math.PI * phase(f.t, 0.01, 0.74));
  if (!cellBackPath.isEmpty && streakPresence > 0.01) {
    ctx.fill(cellBackPath, Shading.color(warpDeep.alpha((f.dark ? 0.22 : 0.36) * streakPresence)));
  }
  for (let i = 0; i < streaks.length; i++) {
    const s = streaks[i];
    const sp = new Path();
    taperedStreak(sp, s.x0, s.y0, s.x1, s.y1, s.wHead, s.wTail);
    ctx.fill(sp, Shading.color(s.color));
  }
  if (!cellCorePath.isEmpty && streakPresence > 0.01) {
    const cg = ctx.copy();
    cg.blendMode = 'plusLighter';
    cg.fill(cellCorePath, Shading.color(warpCore.alpha((f.dark ? 0.72 : 0.85) * streakPresence)));
  }

  // --- Dedicated cinematic hyperspace tunnel star-lines (extending into the bleed) ---
  const tunnelFade = Math.sin(Math.PI * phase(f.t, 0.03, 0.74));
  if (tunnelFade > 0.01) {
    const rayBack = new Path();
    const rayBlue = new Path();
    const rayCore = new Path();
    const rayCount = 72;

    for (let i = 0; i < rayCount; i++) {
      const h0 = closeHash(i, 101, f.seed);
      const h1 = closeHash(i, 211, f.seed);
      const h2 = closeHash(i, 307, f.seed);

      const angle = f.floating
        ? (i / rayCount) * Math.PI * 2 + (h0 - 0.5) * 0.09
        : lerp(0.05, Math.PI - 0.05, (i + h0) / rayCount);

      const start = lerp(0.02, 0.20, h1);
      const dur = lerp(0.36, 0.50, h2);
      const u = phase(f.t, start, start + dur);
      if (u <= 0 || u >= 1) continue;

      const reach = lerp(maxR * 0.45, maxR * 1.18, h0);
      const stretchOut = Math.sin(Math.PI * clamp01(u / 0.36)) * lerp(38, 115, h2);
      const headR = Math.max(0, reach * (1 - easeIn(clamp01(u * 1.20))));
      const tailR = Math.max(headR + 4, (reach + stretchOut) * (1 - easeIn(phase(u, 0.16, 1.0))));

      const ux = Math.cos(angle);
      const uy = Math.sin(angle);
      const x0 = vpX + ux * tailR;
      const y0 = vpY + uy * tailR;
      const x1 = vpX + ux * headR;
      const y1 = vpY + uy * headR;

      const w = lerp(0.95, 2.7, h2 * h2) * Math.sin(Math.PI * u);
      taperedStreak(rayBack, x0, y0, x1, y1, w * 1.38, w * 0.25);
      taperedStreak(rayBlue, x0, y0, x1, y1, w * 1.15, w * 0.18);
      taperedStreak(rayCore, x0 + (x1 - x0) * 0.36, y0 + (y1 - y0) * 0.36, x1, y1, w * 0.54, 0.14);
    }

    if (!rayBack.isEmpty) {
      ctx.fill(rayBack, Shading.color(warpDeep.alpha((f.dark ? 0.24 : 0.38) * tunnelFade)));
    }
    if (!rayBlue.isEmpty) {
      const bg = ctx.copy();
      bg.blendMode = f.dark ? 'plusLighter' : 'normal';
      const rayHue = f.dark ? warpBlue : warpCobalt.mix(warpBlue, 0.65);
      bg.fill(rayBlue, Shading.color(rayHue.alpha(0.86 * tunnelFade)));
    }
    if (!rayCore.isEmpty) {
      const cg = ctx.copy();
      cg.blendMode = 'plusLighter';
      cg.fill(rayCore, Shading.color(warpCore.alpha(0.90 * tunnelFade)));
    }
  }

  // --- Stage 4: Jump flash, soft energy wave & anamorphic lens flare ---
  const flashRise = easeOut(phase(f.t, 0.42, 0.56));
  const flashFall = 1 - easeOut(phase(f.t, 0.56, 0.80));
  const flash = flashRise * flashFall;

  // Feathered radial energy shockwave (replaces thin geometric circle)
  const ringT = phase(f.t, 0.48, 0.74);
  if (ringT > 0 && ringT < 1) {
    const outerR = lerp(12, f.floating ? 124 : 92, easeOut(ringT));
    const innerR = Math.max(0, outerR * lerp(0.45, 0.78, ringT));
    const ringFade = Math.sin(Math.PI * ringT) * (1 - ringT * 0.45);
    const waveRect = new CGRect(vpX - outerR, vpY - outerR, outerR * 2, outerR * 2);

    const wg = ctx.copy();
    wg.blendMode = f.dark ? 'plusLighter' : 'normal';
    wg.fill(
      Path.ellipse(waveRect),
      Shading.radialGradient(
        Gradient.stops([
          [warpBlue.alpha(0.0), 0.0],
          [warpBlue.alpha(0.0), clamp01(innerR / outerR)],
          [warpCyan.alpha((f.dark ? 0.50 : 0.36) * ringFade), 0.88],
          [warpCore.alpha((f.dark ? 0.72 : 0.45) * ringFade), 0.96],
          [warpBlue.alpha(0.0), 1.0],
        ]),
        new CGPoint(vpX, vpY),
        0,
        outerR
      )
    );
  }

  // Single blurred bloom layer for the jump flash + receding star halo (1 blurred draw total)
  const glintT = phase(f.t, 0.54, 0.97);
  const glintAlpha = glintT > 0 && glintT < 1 ? (1 - easeIn(glintT)) * smoothstep(0.54, 0.60, f.t) : 0;
  const bloomLevel = Math.max(flash, glintAlpha * 0.52);

  if (bloomLevel > 0.01) {
    const bloomCtx = ctx.copy();
    bloomCtx.addFilter(Filter.blur(12));
    bloomCtx.drawLayer((layer) => {
      const darkR = lerp(14, 70, flash) + glintAlpha * 10;
      layer.fill(
        Path.ellipse(new CGRect(vpX - darkR, vpY - darkR * 0.70, darkR * 2, darkR * 1.40)),
        Shading.color(warpDeep.alpha(backingStrength * 0.92 * bloomLevel))
      );
      const glowR = lerp(10, 62, flash) + glintAlpha * 16;
      layer.fill(
        Path.ellipse(new CGRect(vpX - glowR, vpY - glowR * 0.70, glowR * 2, glowR * 1.40)),
        Shading.color(warpBlue.alpha(0.88 * bloomLevel))
      );
      if (flash > 0.02) {
        const barW = lerp(34, 300, easeOut(flash));
        const barH = lerp(3, 12, flash);
        layer.fill(
          Path.ellipse(new CGRect(vpX - barW * 0.5, vpY - barH * 0.5, barW, barH)),
          Shading.color(warpCyan.alpha(0.84 * flash))
        );
      }
    });
  }

  // Crisp anamorphic lens flare + central flash core
  if (flash > 0.01) {
    const flareW = lerp(20, 290, easeOut(flash));
    const flareH = lerp(2.0, 9.2, flash);
    const vertH = lerp(8, f.floating ? 64 : 34, flash);

    const flareBack = new Path();
    addDiamondFlare(flareBack, vpX, vpY, flareW * 1.02, flareH * 1.45);
    ctx.fill(flareBack, Shading.color(warpDeep.alpha(backingStrength * 0.72 * flash)));

    const fg = ctx.copy();
    fg.blendMode = f.dark ? 'plusLighter' : 'normal';

    const horiz = new Path();
    addDiamondFlare(horiz, vpX, vpY, flareW, flareH);
    fg.fill(horiz, Shading.color(warpCyan.alpha(0.90 * flash)));

    const vert = new Path();
    addDiamondFlare(vert, vpX, vpY, flareH * 0.85, vertH);
    fg.fill(vert, Shading.color(warpCyan.alpha(0.78 * flash)));

    const cg = ctx.copy();
    cg.blendMode = 'plusLighter';
    const core = new Path();
    addDiamondFlare(core, vpX, vpY, flareW * 0.56, flareH * 0.50);
    addDiamondFlare(core, vpX, vpY, flareH * 0.45, vertH * 0.56);
    cg.fill(core, Shading.color(warpCore.alpha(0.98 * flash)));

    const orbR = lerp(4, 24, flash);
    cg.fill(
      Path.ellipse(new CGRect(vpX - orbR, vpY - orbR, orbR * 2, orbR * 2)),
      Shading.radialGradient(
        Gradient.stops([
          [warpCore.alpha(0.98 * flash), 0.0],
          [warpCyan.alpha(0.68 * flash), 0.45],
          [warpBlue.alpha(0.0), 1.0],
        ]),
        new CGPoint(vpX, vpY),
        0,
        orbR
      )
    );
  }

  // --- Stage 5: Receding point of light & final trailing micro-wisps ---
  if (glintAlpha > 0.01) {
    const latePath = new Path();
    for (let i = 0; i < 10; i++) {
      const h0 = closeHash(i, 701, f.seed);
      const h1 = closeHash(i, 809, f.seed);
      const angle = f.floating
        ? (i / 10) * Math.PI * 2 + h0 * 0.5
        : lerp(0.18, Math.PI - 0.18, (i + h0) / 10);
      const st = lerp(0.56, 0.72, h1);
      const u = phase(f.t, st, st + 0.22);
      if (u <= 0 || u >= 1) continue;
      const startR = lerp(42, 95, h0);
      const headR = startR * (1 - easeIn(clamp01(u * 1.25)));
      const tailR = Math.max(headR + 2, startR * (1 - easeIn(phase(u, 0.15, 1.0))));
      const ux = Math.cos(angle);
      const uy = Math.sin(angle);
      taperedStreak(latePath, vpX + ux * tailR, vpY + uy * tailR, vpX + ux * headR, vpY + uy * headR, 1.15, 0.15);
    }
    if (!latePath.isEmpty) {
      const lg = ctx.copy();
      lg.blendMode = f.dark ? 'plusLighter' : 'normal';
      lg.fill(latePath, Shading.color(warpCyan.alpha(0.75 * glintAlpha)));
    }

    const starScale = 1 - easeIn(glintT);
    const armX = lerp(0.6, 32, starScale);
    const armY = lerp(0.6, 15, starScale);
    const coreR = lerp(0.5, 5.4, starScale);

    const starBack = new Path();
    addDiamondFlare(starBack, vpX, vpY, armX * 1.12, 3.4 * starScale + 0.7);
    addDiamondFlare(starBack, vpX, vpY, 3.4 * starScale + 0.7, armY * 1.12);
    ctx.fill(starBack, Shading.color(warpDeep.alpha(backingStrength * 0.85 * glintAlpha)));

    const sg = ctx.copy();
    sg.blendMode = 'plusLighter';
    const star = new Path();
    addDiamondFlare(star, vpX, vpY, armX, 2.2 * starScale + 0.4);
    addDiamondFlare(star, vpX, vpY, 2.2 * starScale + 0.4, armY);
    sg.fill(star, Shading.color(warpCore.alpha(0.96 * glintAlpha)));
    sg.fill(
      Path.ellipse(new CGRect(vpX - coreR, vpY - coreR, coreR * 2, coreR * 2)),
      Shading.color(warpCore.alpha(glintAlpha))
    );
  }
}
