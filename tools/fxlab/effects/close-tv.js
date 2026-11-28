export const kind = 'close';
export const duration = 0.85;

// Tapered horizontal spindle (thickest at centre, needle-sharp at left & right tips).
function tvSpindlePath(cx, cy, halfW, halfH) {
  const p = new Path();
  if (halfW <= 0.1 || halfH <= 0.05) return p;
  p.move(new CGPoint(cx - halfW, cy));
  p.addQuadCurve(new CGPoint(cx + halfW, cy), new CGPoint(cx, cy - halfH * 1.8));
  p.addQuadCurve(new CGPoint(cx - halfW, cy), new CGPoint(cx, cy + halfH * 1.8));
  p.closeSubpath();
  return p;
}

// Tapered vertical spindle for the phosphor dot's diffraction cross-glint.
function tvVerticalSpindlePath(cx, cy, halfW, halfH) {
  const p = new Path();
  if (halfW <= 0.05 || halfH <= 0.1) return p;
  p.move(new CGPoint(cx, cy - halfH));
  p.addQuadCurve(new CGPoint(cx, cy + halfH), new CGPoint(cx + halfW * 1.8, cy));
  p.addQuadCurve(new CGPoint(cx, cy - halfH), new CGPoint(cx - halfW * 1.8, cy));
  p.closeSubpath();
  return p;
}

export function draw(f, ctx) {
  if (f.t <= 0.001) {
    f.drawPad(ctx);
    return;
  }

  const t = f.t;
  const pad = f.pad;
  const cx = pad.midX;

  // Stage 1-2: Vertical deflection collapses quickly from the very first frames into a razor line.
  const vRaw = phase(t, 0.01, 0.45);
  const vEase = lerp(easeIn(vRaw), easeInOut(vRaw), 0.62);

  // Stage 2-3: Capacitor-surge horizontal bloom (+3% width), then horizontal coil snaps to a dot.
  const surge = Math.sin(Math.PI * phase(t, 0.02, 0.40));
  const hRaw = phase(t, 0.41, 0.72);
  const hEase = easeInOut(hRaw);

  // Target Y: floating collapses at pad centre; docked collapses cleanly to the notch lip and tucks in.
  const sinkY = f.floating ? f.sink.midY : f.sink.maxY + 4;
  const cyLift = easeInOut(phase(t, 0.04, 0.50));
  let cy = lerp(pad.midY, sinkY, cyLift);
  if (!f.floating) {
    cy = cy - 10 * easeIn(phase(t, 0.74, 1.0));
  }

  const w = lerp(pad.width * (1 + 0.03 * surge), 4.0, hEase);
  const h = lerp(pad.height, 2.4, vEase);

  // Subtle horizontal sync jitter as the power supply cuts out.
  const joltEnv = Math.sin(Math.PI * phase(t, 0.01, 0.24));
  const joltStep = Math.floor(t * 30);
  const joltX = (closeHash(joltStep, 11, f.seed) - 0.5) * 7.0 * joltEnv;

  const topY = f.floating ? (cy - h / 2) : Math.max(pad.minY, cy - h / 2);
  const r = new CGRect(cx - w / 2 + joltX, topY, w, h);
  const beamCy = r.midY;

  // Iconic CRT P4/P22 phosphor cyan-white, harmonised with the pad's theme accent.
  const crtCyan = new RGBA(0.60, 0.90, 1.0, 1);
  const crtAccent = crtCyan.mix(f.accent, 0.38);
  const crtDeep = new RGBA(0.18, 0.52, 0.80, 1).mix(f.accent, 0.40);

  // --- Stage 1 & 2: Collapsing pad with 3-gun RGB convergence slip, scanlines & beam concentration ---
  const padFade = 1 - phase(t, 0.38, 0.51);
  if (padFade > 0.005) {
    const clipPath = f.padPathIn(r);
    const gPad = ctx.copy();
    gPad.clip(clipPath);

    // Main collapsing pad picture, brightening smoothly as vertical scanlines pack together.
    const gMain = gPad.copy();
    const boost = (f.dark ? 0.42 : 0.25) * easeIn(vRaw);
    if (boost > 0.01) {
      gMain.addFilter(Filter.brightness(boost));
    }
    f.drawPad(gMain, r, padFade);

    // 3-gun RGB convergence slip: red & cyan guns lose vertical deflection at slightly different rates.
    const splitAmt = Math.sin(Math.PI * phase(t, 0.02, 0.44));
    if (splitAmt > 0.02 && h > 5) {
      const rShiftX = -5.5 * splitAmt;
      const rExtraH = h * 0.09 * splitAmt;
      const rRect = new CGRect(r.minX + rShiftX, r.minY - rExtraH * 0.5, r.width, r.height + rExtraH);
      const gRed = gPad.copy();
      gRed.blendMode = f.dark ? 'plusLighter' : 'multiply';
      gRed.addFilter(Filter.colorMultiply(new RGBA(1.0, 0.20, 0.30, 1)));
      f.drawPad(gRed, rRect, (f.dark ? 0.52 : 0.24) * splitAmt * padFade);

      const bShiftX = 5.5 * splitAmt;
      const bShrinkH = h * 0.08 * splitAmt;
      const bRect = new CGRect(r.minX + bShiftX, r.minY + bShrinkH * 0.5, r.width, Math.max(2, r.height - bShrinkH));
      const gBlue = gPad.copy();
      gBlue.blendMode = f.dark ? 'plusLighter' : 'multiply';
      gBlue.addFilter(Filter.colorMultiply(new RGBA(0.15, 0.90, 1.0, 1)));
      f.drawPad(gBlue, bRect, (f.dark ? 0.52 : 0.24) * splitAmt * padFade);
    }

    // Crisp horizontal CRT scanlines merged into one path fill.
    const scanIn = easeOut(phase(t, 0.01, 0.14)) * (1 - phase(t, 0.36, 0.48));
    if (scanIn > 0.01 && h > 8) {
      const scanPath = new Path();
      const pitch = 3.5;
      let sy = r.minY + 1.0;
      while (sy < r.maxY) {
        scanPath.addRect(new CGRect(r.minX, sy, r.width, 1.25));
        sy += pitch;
      }
      gPad.fill(scanPath, Shading.color(new RGBA(0, 0, 0, (f.dark ? 0.36 : 0.24) * scanIn * padFade)));
    }

    // Brief analog retrace/static flicker lines sweeping inside the collapsing tube.
    const retraceEnv = Math.sin(Math.PI * phase(t, 0.03, 0.42));
    if (retraceEnv > 0.05 && h > 10) {
      const retracePath = new Path();
      const step = Math.floor(t * 24);
      for (let i = 0; i < 3; i++) {
        const ny = closeHash(step, i + 31, f.seed);
        const ly = r.minY + ny * r.height;
        retracePath.addRect(new CGRect(r.minX, ly, r.width, 1.0));
      }
      gPad.fill(retracePath, Shading.color(crtAccent.mix(RGBA.white, 0.6).alpha(0.32 * retraceEnv * padFade)));
    }

    // Tube edge darkening + luminous phosphor concentration band along the horizontal midline.
    const vigAlpha = easeOut(phase(t, 0.04, 0.30)) * padFade;
    const coreGlow = easeIn(phase(t, 0.10, 0.44)) * padFade;
    const edgeDark = f.dark ? 0.48 : 0.28;
    const grad = Gradient.stops([
      [new RGBA(0.01, 0.02, 0.05, edgeDark * vigAlpha), 0.0],
      [new RGBA(0.01, 0.02, 0.05, 0.0), 0.22],
      [crtAccent.mix(RGBA.white, 0.72).alpha(0.92 * coreGlow), 0.50],
      [new RGBA(0.01, 0.02, 0.05, 0.0), 0.78],
      [new RGBA(0.01, 0.02, 0.05, edgeDark * vigAlpha), 1.0],
    ]);
    gPad.fill(clipPath, Shading.linearGradient(grad, new CGPoint(r.midX, r.minY), new CGPoint(r.midX, r.maxY)));

    // Power-cut surge: crisp luminous central scan-band instead of a flat grey wash.
    const initFlash = Math.sin(Math.PI * phase(t, 0.005, 0.14));
    if (initFlash > 0.01) {
      const bandH = Math.max(6, r.height * 0.28);
      const bandGrad = Gradient.stops([
        [crtAccent.alpha(0.0), 0.0],
        [RGBA.white.alpha(0.34 * initFlash), 0.5],
        [crtAccent.alpha(0.0), 1.0],
      ]);
      gPad.fill(
        Path.rect(new CGRect(r.minX, beamCy - bandH * 0.5, r.width, bandH)),
        Shading.linearGradient(bandGrad, new CGPoint(r.midX, beamCy - bandH * 0.5), new CGPoint(r.midX, beamCy + bandH * 0.5))
      );
    }
  }

  // --- Stage 3: Searing horizontal electron beam & bloom ---
  const beamIn = easeOut(phase(t, 0.24, 0.43));
  const beamOut = 1 - phase(t, 0.69, 0.76);
  const beamAlpha = beamIn * beamOut;

  if (beamAlpha > 0.005) {
    const halfW = w * 0.5;
    const energy = 1.0 + 0.5 * Math.sin(Math.PI * phase(t, 0.42, 0.74));
    const coreHalfH = lerp(2.3, 1.4, hEase) * (0.85 + 0.25 * energy);

    // Soft cool-tinted contrast backing so the white-hot beam reads vividly on white desktops too.
    const gBack = ctx.copy();
    gBack.addFilter(Filter.blur(5));
    gBack.fill(
      tvSpindlePath(cx + joltX, beamCy, halfW + 8, coreHalfH + 3.6),
      Shading.color(crtDeep.mix(RGBA.black, 0.55).alpha(0.32 * beamAlpha))
    );

    // Wide + inner phosphor bloom in one blurred additive layer.
    const gBloom = ctx.copy();
    gBloom.blendMode = 'plusLighter';
    gBloom.addFilter(Filter.blur(9));
    gBloom.drawLayer((layer) => {
      layer.fill(
        tvSpindlePath(cx + joltX, beamCy, halfW + 14, coreHalfH * 3.4),
        Shading.color(crtAccent.alpha(0.82 * beamAlpha))
      );
      layer.fill(
        tvSpindlePath(cx + joltX, beamCy, halfW * 0.78, coreHalfH * 1.9),
        Shading.color(RGBA.white.alpha(0.62 * beamAlpha))
      );
    });

    // Crisp unblurred needle-sharp white-hot core.
    const beamGrad = Gradient.stops([
      [crtAccent.alpha(0.0), 0.0],
      [crtAccent.mix(RGBA.white, 0.72).alpha(0.95 * beamAlpha), 0.12],
      [RGBA.white.alpha(beamAlpha), 0.50],
      [crtAccent.mix(RGBA.white, 0.72).alpha(0.95 * beamAlpha), 0.88],
      [crtAccent.alpha(0.0), 1.0],
    ]);
    ctx.fill(
      tvSpindlePath(cx + joltX, beamCy, halfW + 2, coreHalfH),
      Shading.linearGradient(beamGrad, new CGPoint(cx - halfW - 2, beamCy), new CGPoint(cx + halfW + 2, beamCy))
    );
  }

  // --- Stage 4 & 5: Phosphor dot flare, diffraction cross-glint & deliberate lingering afterglow ---
  const dotIn = easeOut(phase(t, 0.62, 0.71));
  const dotOut = 1 - phase(t, 0.73, 1.0);
  if (dotIn > 0.005 && dotOut > 0.005) {
    const flare = Math.sin(Math.PI * phase(t, 0.63, 0.82));
    const coreLife = Math.pow(clamp01(1 - phase(t, 0.72, 0.96)), 1.35);
    const glowLife = Math.pow(clamp01(dotOut), 1.15);

    // Phosphor cools visibly from pure white -> vivid cyan-accent -> deep ember before winking out.
    const coolT = easeOut(phase(t, 0.72, 0.98));
    const haloColor = crtAccent.mix(crtDeep, coolT);
    const dotPos = new CGPoint(cx, beamCy);

    // Subtle tinted contrast backing for light/white desktops.
    const backR = lerp(17, 5, coolT) * dotIn;
    if (backR > 0.5) {
      const backCol = crtDeep.mix(RGBA.black, 0.45);
      const backGrad = Gradient.stops([
        [backCol.alpha(0.28 * glowLife * dotIn), 0.0],
        [backCol.alpha(0.0), 1.0],
      ]);
      ctx.fill(
        Path.ellipse(new CGRect(cx - backR, beamCy - backR, backR * 2, backR * 2)),
        Shading.radialGradient(backGrad, dotPos, 0, backR)
      );
    }

    // Outer lingering phosphor afterglow halo (radial gradient = fast, zero extra blur).
    const outerR = lerp(30, 8, coolT) * dotIn + 14 * flare;
    const outerGrad = Gradient.stops([
      [RGBA.white.mix(haloColor, 0.35 + 0.60 * coolT).alpha(0.92 * glowLife * dotIn), 0.0],
      [haloColor.alpha(0.52 * glowLife * dotIn), 0.34],
      [crtDeep.alpha(0.18 * glowLife * dotIn), 0.68],
      [crtDeep.alpha(0.0), 1.0],
    ]);
    const gGlow = ctx.copy();
    gGlow.blendMode = 'plusLighter';
    gGlow.fill(
      Path.ellipse(new CGRect(cx - outerR, beamCy - outerR, outerR * 2, outerR * 2)),
      Shading.radialGradient(outerGrad, dotPos, 0, outerR)
    );

    // Brief diffraction cross-glint right when the horizontal beam snaps into the dot.
    if (flare > 0.02) {
      gGlow.fill(
        tvSpindlePath(cx, beamCy, 36 * flare, 1.5 * flare),
        Shading.color(RGBA.white.alpha(0.88 * flare))
      );
      gGlow.fill(
        tvVerticalSpindlePath(cx, beamCy, 1.3 * flare, 16 * flare),
        Shading.color(crtAccent.mix(RGBA.white, 0.65).alpha(0.74 * flare))
      );
    }

    // Crisp phosphor core bead that shrinks smoothly and cools to a glowing ember.
    const coreR = lerp(6.0, 1.0, easeOut(phase(t, 0.72, 0.98))) * dotIn + 2.2 * flare;
    if (coreR > 0.3 && glowLife > 0.01) {
      const coreColor = RGBA.white.mix(haloColor, coolT * 0.60).alpha(Math.max(coreLife, glowLife * 0.75) * dotIn);
      ctx.fill(
        Path.ellipse(new CGRect(cx - coreR, beamCy - coreR, coreR * 2, coreR * 2)),
        Shading.color(coreColor)
      );
    }
  }
}
