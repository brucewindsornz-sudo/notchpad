// Melt ("Liquid metal") closing animation: the pad liquefies into mirror-bright
// mercury with soft 3D chrome reflections and specular glints, flowing upward in
// curved meniscus tendrils into the notch (docked) or dripping and coalescing
// seamlessly into a trembling mercury bead (floating).

export const kind = 'close';
export const duration = 1.0;

// Draw a single glossy mercury droplet / teardrop at (cx, cy) with radii (rx, ry).
function drawMercuryBead(ctx, cx, cy, rx, ry, stretchY, chromeBright, chromeSilver, chromeDark, alpha) {
  if (rx < 0.6 || ry < 0.6 || alpha <= 0.02) return;

  const p = new Path();
  if (Math.abs(stretchY) < 0.15) {
    p.addEllipse(new CGRect(cx - rx, cy - ry, rx * 2.0, ry * 2.0));
  } else {
    const tipY = cy + stretchY * ry * 2.2;
    const baseY = cy - Math.sign(stretchY) * ry * 0.85;
    p.move(new CGPoint(cx, tipY));
    p.addCurve(
      new CGPoint(cx + rx, cy),
      new CGPoint(cx + rx * 0.45, lerp(tipY, cy, 0.55)),
      new CGPoint(cx + rx, lerp(cy, tipY, 0.25))
    );
    p.addCurve(
      new CGPoint(cx, baseY),
      new CGPoint(cx + rx, lerp(cy, baseY, 0.62)),
      new CGPoint(cx + rx * 0.55, baseY)
    );
    p.addCurve(
      new CGPoint(cx - rx, cy),
      new CGPoint(cx - rx * 0.55, baseY),
      new CGPoint(cx - rx, lerp(cy, baseY, 0.62))
    );
    p.addCurve(
      new CGPoint(cx, tipY),
      new CGPoint(cx - rx, lerp(cy, tipY, 0.25)),
      new CGPoint(cx - rx * 0.45, lerp(tipY, cy, 0.55))
    );
    p.closeSubpath();
  }

  const maxR = Math.max(rx, ry) * 1.45;
  const hiPt = new CGPoint(cx - rx * 0.30, cy - ry * 0.32);
  ctx.fill(
    p,
    Shading.radialGradient(
      Gradient.stops([
        [RGBA.white.alpha(alpha), 0.0],
        [chromeBright.alpha(alpha), 0.22],
        [chromeSilver.alpha(alpha), 0.48],
        [chromeDark.alpha(alpha), 0.78],
        [chromeSilver.alpha(alpha * 0.92), 1.0],
      ]),
      hiPt,
      0.0,
      maxR
    )
  );

  ctx.stroke(p, Shading.color(chromeDark.alpha(0.55 * alpha)), 0.9);

  const sr = Math.max(0.9, rx * 0.28);
  ctx.fill(
    Path.ellipse(new CGRect(cx - rx * 0.36 - sr * 0.6, cy - ry * 0.36 - sr * 0.45, sr * 1.3, sr * 0.9)),
    Shading.color(RGBA.white.alpha(0.95 * alpha))
  );
}

// Compute the docked liquid-mercury lower boundary Y for normalized u in [0, 1].
function dockedDripY(u, t, pad, sink, seed) {
  const s1 = (seed + 31) >>> 0;
  const s2 = (seed + 89) >>> 0;

  const sag = Math.sin(Math.PI * phase(t, 0.0, 0.26)) * 22.0;
  const drain = easeInOut(phase(t, 0.14, 0.84));
  const finalPull = easeIn(phase(t, 0.70, 0.89));

  // Outer sides curve upward much earlier than the central heavy mercury tendrils,
  // creating a natural concave liquid-metal funnel into the notch.
  const cDist = Math.abs(u - 0.5) * 2.0;
  const funnel = Math.pow(cDist, 1.8) * 0.46 * smoothstep(0.08, 0.60, t);
  const edgeDrain = clamp01(drain * 1.18 + funnel);

  // Smooth bulbous hanging mercury lobes (strongest near centre).
  const lobePhase = smoothstep(0.02, 0.18, t) * (1.0 - smoothstep(0.64, 0.88, t));
  const w1 = Math.pow(0.5 + 0.5 * Math.sin(u * Math.PI * 5.0 + closeHash(1, 2, s1) * 3.0), 2.4);
  const w2 = Math.pow(0.5 + 0.5 * Math.sin(u * Math.PI * 9.0 + closeHash(3, 4, s2) * 4.0 + t * 2.0), 2.8);
  const n = closeNoise(u * 4.2 + 0.4, t * 2.2, s1);
  const dripExtra = (w1 * 42.0 + w2 * 20.0 + n * 14.0) * lobePhase * (1.0 - cDist * 0.52);

  const baseBottom = lerp(pad.maxY + sag, sink.maxY + 4.0, edgeDrain);
  const y = baseBottom + dripExtra * (1.0 - finalPull);
  return lerp(y, sink.minY - 2.0, finalPull);
}

// Draw soft, organic 3D chrome reflections clipped inside bodyPath (1 blurred drawLayer).
function drawChromeReflections(ctx, bodyPath, bLeft, bRight, bTop, bBot, t, chromeDark, alpha) {
  const bw = Math.max(4.0, bRight - bLeft);
  const bh = Math.max(4.0, bBot - bTop);
  const gRef = ctx.copy();
  gRef.clip(bodyPath);
  gRef.opacity = alpha;
  gRef.addFilter(Filter.blur(9.0));
  gRef.drawLayer((layer) => {
    // Upper sky-bright specular caustic band.
    const y1 = bTop + bh * (0.16 + Math.sin(t * 6.0) * 0.04);
    const p1 = new Path();
    p1.addEllipse(new CGRect(bLeft + bw * 0.08, y1 - bh * 0.08, bw * 0.72, bh * 0.18));
    layer.fill(p1, Shading.color(RGBA.white.alpha(0.65)));

    // Deep undulating dark horizon trough (gives liquid mercury its signature high contrast).
    const y2 = bTop + bh * (0.48 + Math.sin(t * 7.2 + 1.1) * 0.05);
    const p2 = new Path();
    for (let i = 0; i <= 16; i++) {
      const u = i / 16.0;
      const x = bLeft - 10.0 + u * (bw + 20.0);
      const y = y2 + Math.sin(u * Math.PI * 2.5 + t * 6.5) * (bh * 0.07);
      const pt = new CGPoint(x, y);
      if (i === 0) p2.move(pt);
      else p2.addLine(pt);
    }
    layer.stroke(
      p2,
      Shading.color(chromeDark.alpha(0.72)),
      { lineWidth: Math.max(6.0, bh * 0.14), lineCap: 'round', lineJoin: 'round' }
    );

    // Lower bright ground-bounce specular curve.
    const y3 = bTop + bh * (0.76 + Math.cos(t * 6.8) * 0.04);
    const p3 = new Path();
    p3.addEllipse(new CGRect(bLeft + bw * 0.18, y3 - bh * 0.07, bw * 0.64, bh * 0.14));
    layer.fill(p3, Shading.color(RGBA.white.alpha(0.55)));
  });
}

// Draw a crisp 4-point chrome specular star-glint.
function drawStarGlint(ctx, gx, gy, pulse, maxR, chromeBright) {
  if (pulse <= 0.01) return;
  const starR = (8.0 + pulse * maxR) * pulse;
  const starW = 1.7 * pulse;
  const sp = new Path();
  sp.move(new CGPoint(gx, gy - starR * 0.85));
  sp.addLine(new CGPoint(gx + starW, gy - starW));
  sp.addLine(new CGPoint(gx + starR, gy));
  sp.addLine(new CGPoint(gx + starW, gy + starW));
  sp.addLine(new CGPoint(gx, gy + starR * 0.85));
  sp.addLine(new CGPoint(gx - starW, gy + starW));
  sp.addLine(new CGPoint(gx - starR, gy));
  sp.addLine(new CGPoint(gx - starW, gy - starW));
  sp.closeSubpath();

  const gBloom = ctx.copy();
  gBloom.addFilter(Filter.blur(4.0));
  gBloom.fill(sp, Shading.color(chromeBright.alpha(0.75 * pulse)));
  ctx.fill(sp, Shading.color(RGBA.white.alpha(0.95 * pulse)));
}

export function draw(f, ctx) {
  const t = f.t;
  if (t >= 1.0) return;

  if (t <= 0.0001) {
    f.drawPad(ctx);
    return;
  }

  const pad = f.pad;
  const sink = f.sink;
  const padW = pad.width;
  const padH = pad.height;
  const seed = f.seed;

  // High-contrast mirror mercury palette with subtle theme accent tint.
  const chromeBright = new RGBA(0.95, 0.97, 1.0, 1.0).mix(f.accent, 0.08);
  const chromeSilver = new RGBA(0.75, 0.79, 0.86, 1.0).mix(f.accent, 0.12);
  const chromeMid = new RGBA(0.44, 0.48, 0.55, 1.0).mix(f.accent, 0.10);
  const chromeDark = new RGBA(0.08, 0.10, 0.14, 1.0).mix(f.bg, 0.14);

  const metalBlend = smoothstep(0.06, 0.44, t);
  const padReveal = 1.0 - smoothstep(0.14, 0.46, t);

  if (!f.floating) {
    // =========================================================================
    // DOCKED MODE: liquefies and drains upward in curved chrome tendrils into f.sink
    // =========================================================================
    const bodyAlive = t < 0.89;
    const narrow = easeInOut(phase(t, 0.16, 0.84));
    const finalPinch = easeIn(phase(t, 0.72, 0.88));
    const leftX = lerp(pad.minX, sink.minX + 10.0, narrow);
    const rightX = lerp(pad.maxX, sink.maxX - 10.0, narrow);
    const curL = lerp(leftX, sink.midX - 8.0, finalPinch);
    const curR = lerp(rightX, sink.midX + 8.0, finalPinch);
    const curW = Math.max(2.0, curR - curL);

    if (bodyAlive) {
      const samples = 56;
      const topY = pad.minY;
      const topInset = lerp(12.0, 2.0, narrow);
      const bodyLeftX = curL + topInset;
      const bodyRightX = curR - topInset;
      const innerW = Math.max(2.0, bodyRightX - bodyLeftX);
      const cornerR = lerp(22.0, 6.0, narrow);

      const bodyPath = new Path();
      bodyPath.move(new CGPoint(curL, topY));
      bodyPath.addLine(new CGPoint(curR, topY));
      bodyPath.addQuadCurve(
        new CGPoint(bodyRightX, topY + topInset),
        new CGPoint(bodyRightX, topY)
      );

      // Curved meniscus right edge tapering inward as the mercury pulls up.
      const yRight = dockedDripY(1.0, t, pad, sink, seed);
      const meniscusPull = innerW * 0.12 * smoothstep(0.20, 0.75, t);
      bodyPath.addQuadCurve(
        new CGPoint(bodyRightX - meniscusPull, Math.max(topY + topInset, yRight - cornerR * 0.6)),
        new CGPoint(bodyRightX, lerp(topY + topInset, yRight, 0.45))
      );

      // Smooth bulbous drip contour from right to left.
      for (let i = samples; i >= 0; i--) {
        const u = i / samples;
        const x = lerp(bodyLeftX + meniscusPull, bodyRightX - meniscusPull, u);
        let y = dockedDripY(u, t, pad, sink, seed);
        const edgeU = Math.min(u, 1.0 - u);
        if (edgeU < 0.06) {
          const cf = 1.0 - edgeU / 0.06;
          y -= cf * cf * cornerR * (1.0 - narrow * 0.65);
        }
        bodyPath.addLine(new CGPoint(x, Math.max(topY + 1.0, y)));
      }

      // Curved meniscus left edge back up to the top flare.
      const yLeft = dockedDripY(0.0, t, pad, sink, seed);
      bodyPath.addQuadCurve(
        new CGPoint(bodyLeftX, topY + topInset),
        new CGPoint(bodyLeftX, lerp(topY + topInset, yLeft, 0.45))
      );
      bodyPath.addQuadCurve(
        new CGPoint(curL, topY),
        new CGPoint(bodyLeftX, topY)
      );
      bodyPath.closeSubpath();

      // 1. Melting pad texture drawn inside ONE opacity layer so strips have zero seams.
      if (padReveal > 0.01) {
        const gPad = ctx.copy();
        gPad.clip(bodyPath);
        gPad.opacity = padReveal;
        if (t < 0.06) {
          f.drawPad(gPad, pad, 1.0);
        } else {
          gPad.drawLayer((layer) => {
            const strips = 24;
            const spanL = bodyLeftX;
            const spanW = innerW;
            for (let i = 0; i < strips; i++) {
              const u = (i + 0.5) / strips;
              const targetY = dockedDripY(u, t, pad, sink, seed);
              const scaleY = Math.max(0.08, (targetY - pad.minY) / padH);
              const dstX = spanL + (i / strips) * spanW;
              const dstW = spanW / strips + 0.6;
              const gStrip = layer.copy();
              gStrip.clip(Path.rect(new CGRect(dstX - 0.2, pad.minY, dstW, Math.max(4.0, targetY - pad.minY + 4.0))));
              f.drawPad(gStrip, new CGRect(spanL, pad.minY, spanW, padH * scaleY), 1.0);
            }
          });
        }
      }

      // 2. Liquid-chrome metallic shading + soft blurred 3D reflections.
      if (metalBlend > 0.01) {
        const bb = bodyPath.boundingRect;
        const bTop = bb.minY;
        const bBot = Math.max(bTop + 8.0, bb.maxY);
        const horizonShift = Math.sin(t * 7.5) * 0.05;
        const chromeAlpha = metalBlend * (1.0 - phase(t, 0.82, 0.89));

        const gChrome = ctx.copy();
        gChrome.opacity = chromeAlpha;
        gChrome.fill(
          bodyPath,
          Shading.linearGradient(
            Gradient.stops([
              [chromeBright, 0.0],
              [chromeSilver, 0.22],
              [chromeDark, clamp01(0.46 + horizonShift)],
              [chromeMid, clamp01(0.56 + horizonShift)],
              [chromeBright, 0.78],
              [chromeDark.mix(chromeMid, 0.35), 1.0],
            ]),
            new CGPoint(pad.midX - curW * 0.14, bTop),
            new CGPoint(pad.midX + curW * 0.14, bBot)
          )
        );

        drawChromeReflections(ctx, bodyPath, bb.minX, bb.maxX, bTop, bBot, t, chromeDark, chromeAlpha);

        // Crisp specular rim hugging just inside the bulbous lower drips.
        const gRimHi = ctx.copy();
        gRimHi.clip(bodyPath);
        const hiLine = new Path();
        for (let i = 3; i <= samples - 3; i++) {
          const u = i / samples;
          const x = lerp(bodyLeftX + meniscusPull, bodyRightX - meniscusPull, u);
          const y = dockedDripY(u, t, pad, sink, seed) - 5.0;
          const pt = new CGPoint(x, Math.max(topY + 2.0, y));
          if (i === 3) hiLine.move(pt);
          else hiLine.addLine(pt);
        }
        gRimHi.stroke(
          hiLine,
          Shading.color(RGBA.white.alpha(0.75 * chromeAlpha * (1.0 - finalPinch))),
          { lineWidth: 2.2, lineCap: 'round', lineJoin: 'round' }
        );

        // Dark metallic contour stroke so mercury pops on white desktops.
        gChrome.stroke(bodyPath, Shading.color(chromeDark.alpha(0.65)), 1.3);
      }

      // 2b. Early liquefaction chrome sheen wave sweeping upward (t = 0.00..0.30).
      const sheenP = phase(t, 0.0, 0.30);
      if (sheenP > 0.0 && sheenP < 1.0) {
        const gSheen = ctx.copy();
        gSheen.clip(bodyPath);
        const sheenY = lerp(pad.maxY + 30.0, pad.minY - 30.0, easeInOut(sheenP));
        const sheenAlpha = Math.sin(Math.PI * sheenP) * 0.72;
        gSheen.fill(
          Path.rect(new CGRect(pad.minX - 10.0, sheenY - 38.0, padW + 20.0, 76.0)),
          Shading.linearGradient(
            Gradient.stops([
              [RGBA.white.alpha(0.0), 0.0],
              [chromeBright.alpha(sheenAlpha), 0.42],
              [RGBA.white.alpha(sheenAlpha * 1.15), 0.52],
              [chromeDark.alpha(sheenAlpha * 0.45), 0.68],
              [RGBA.white.alpha(0.0), 1.0],
            ]),
            new CGPoint(pad.midX, sheenY - 38.0),
            new CGPoint(pad.midX, sheenY + 38.0)
          )
        );
      }
    }

    // 3. Detached mercury beads pinching off and snapping upward into the notch.
    const sDrop = (seed + 503) >>> 0;
    const dropCount = 16;
    for (let i = 0; i < dropCount; i++) {
      const u = 0.12 + closeHash(i, 1, sDrop) * 0.76;
      const startT = 0.14 + closeHash(i, 2, sDrop) * 0.40;
      const lifeLen = 0.28 + closeHash(i, 3, sDrop) * 0.20;
      const life = phase(t, startT, startT + lifeLen);
      if (life <= 0.0 || life >= 1.0) continue;

      const spawnX = lerp(pad.minX + u * padW, sink.midX, easeInOut(phase(startT, 0.16, 0.84)) * 0.7);
      const spawnY = Math.min(pad.maxY + 36.0, dockedDripY(u, startT, pad, sink, seed) + 4.0);
      const targetX = sink.midX + (closeHash(i, 4, sDrop) - 0.5) * (sink.width * 0.52);
      const targetY = sink.minY + 6.0;

      const dip = Math.sin(Math.PI * Math.min(1.0, life * 2.2)) * (10.0 + closeHash(i, 5, sDrop) * 14.0);
      const pull = easeIn(life);
      const cx = lerp(spawnX, targetX, easeInOut(life));
      const cy = lerp(spawnY, targetY, pull) + dip * (1.0 - pull);

      const baseR = 3.2 + closeHash(i, 6, sDrop) * 6.2;
      const shrink = 1.0 - easeIn(phase(life, 0.68, 1.0)) * 0.85;
      const rx = baseR * shrink * (1.0 - 0.25 * pull);
      const ry = baseR * shrink * (1.0 + 0.65 * pull);
      const alpha = smoothstep(0.0, 0.12, life) * (1.0 - phase(life, 0.85, 1.0));
      drawMercuryBead(ctx, cx, cy, rx, ry, -pull * 0.9, chromeBright, chromeSilver, chromeDark, alpha);
    }

    // 4. Final chrome bead slipping into the notch + crisp star-glint (t = 0.80..0.99).
    const glintLife = phase(t, 0.80, 0.99);
    if (glintLife > 0.0 && glintLife < 1.0) {
      const gx = sink.midX;
      const gy = sink.minY + 8.0;
      const pulse = Math.sin(Math.PI * glintLife);
      const lastR = lerp(8.5, 0.8, easeIn(glintLife));
      drawMercuryBead(ctx, gx, gy + (1.0 - glintLife) * 6.0, lastR * 1.25, lastR * 0.7, 0.0, chromeBright, chromeSilver, chromeDark, pulse);
      drawStarGlint(ctx, gx, gy, pulse, 18.0, chromeBright);
    }
  } else {
    // =========================================================================
    // FLOATING MODE: smooth organic morph from rounded card -> dripping mercury
    // blob -> seamless trembling mercury sphere -> pinpoint star-glint.
    // =========================================================================
    const poolX = pad.midX;
    const poolY = pad.midY + padH * 0.14;

    // Continuous morph from pad card (t=0) to mercury sphere (t=0.68) to pinpoint (t=0.96).
    const morphP = easeInOut(phase(t, 0.12, 0.68));
    const shrinkP = easeIn(phase(t, 0.66, 0.96));
    const wobble = Math.sin(t * 24.0) * 0.11 * smoothstep(0.45, 0.68, t) * (1.0 - shrinkP);

    if (shrinkP < 0.995) {
      // Current bounding half-extents smoothly interpolating from pad -> sphere -> pinpoint.
      const cx = poolX;
      const cy = lerp(pad.midY, poolY, morphP);
      const rxBase = lerp(padW * 0.5, 48.0, morphP);
      const ryBase = lerp(padH * 0.5, 42.0, morphP);
      const rx = lerp(rxBase, 1.2, shrinkP) * (1.0 + wobble);
      const ry = lerp(ryBase, 1.2, shrinkP) * (1.0 - wobble);

      // Superellipse exponent smoothly morphs from liquid-rounded card (n = 6) to pure ellipse (n = 2).
      const superExp = lerp(6.0, 2.0, smoothstep(0.0, 0.72, morphP));
      const dripAmp = smoothstep(0.04, 0.32, t) * (1.0 - smoothstep(0.46, 0.68, t));
      const s1 = (seed + 41) >>> 0;
      const s2 = (seed + 97) >>> 0;

      // Sample 140 points around the closed organic silhouette (smooth rounded drips, zero corners).
      const pts = 140;
      const bodyPath = new Path();
      for (let i = 0; i < pts; i++) {
        const ang = (i / pts) * Math.PI * 2.0;
        const ca = Math.cos(ang);
        const sa = Math.sin(ang);
        // Superellipse coordinates: smooth rounded card at n=12, perfect circle/ellipse at n=2.
        const sx = Math.sign(ca) * Math.pow(Math.abs(ca), 2.0 / superExp);
        const sy = Math.sign(sa) * Math.pow(Math.abs(sa), 2.0 / superExp);

        let px = cx + sx * rx;
        let py = cy + sy * ry;

        // Add hanging viscous mercury drips along the bottom hemisphere (sa > 0.05).
        if (dripAmp > 0.005 && sa > 0.05) {
          const u = 0.5 + sx * 0.5;
          const botMask = Math.pow(Math.max(0.0, sa), 1.5);
          const w1 = Math.pow(0.5 + 0.5 * Math.sin(u * Math.PI * 5.0 + closeHash(2, 1, s1) * 3.0), 1.8);
          const w2 = Math.pow(0.5 + 0.5 * Math.sin(u * Math.PI * 8.0 + closeHash(4, 3, s2) * 3.5 + t * 2.0), 2.0);
          const n = closeNoise(u * 4.0 + 1.1, t * 2.0, s1);
          py += (w1 * 48.0 + w2 * 20.0 + n * 14.0) * dripAmp * botMask;
        }

        const pt = new CGPoint(px, py);
        if (i === 0) bodyPath.move(pt);
        else bodyPath.addLine(pt);
      }
      bodyPath.closeSubpath();

      // 1. Melting pad texture inside ONE opacity layer (zero seams).
      if (padReveal > 0.01) {
        const gPad = ctx.copy();
        gPad.clip(bodyPath);
        gPad.opacity = padReveal;
        if (t < 0.06) {
          gPad.clip(f.padPath);
          f.drawPad(gPad, pad, 1.0);
        } else {
          gPad.drawLayer((layer) => {
            const bb = bodyPath.boundingRect;
            const strips = 24;
            for (let i = 0; i < strips; i++) {
              const u = (i + 0.5) / strips;
              const dstX = bb.minX + (i / strips) * bb.width;
              const dstW = bb.width / strips + 0.6;
              const dripStretch = Math.pow(0.5 + 0.5 * Math.sin(u * Math.PI * 5.0 + closeHash(2, 1, s1) * 3.0), 2.0) * 38.0 * dripAmp;
              const gStrip = layer.copy();
              gStrip.clip(Path.rect(new CGRect(dstX - 0.2, bb.minY - 4.0, dstW, bb.height + 8.0)));
              f.drawPad(gStrip, new CGRect(bb.minX, bb.minY, bb.width, Math.max(12.0, (ry * 2.0) + dripStretch)), 1.0);
            }
          });
        }
      }

      // 2. Mirror-chrome shading that transitions seamlessly from flat metallic horizon to spherical bead!
      if (metalBlend > 0.01) {
        const bb = bodyPath.boundingRect;
        const sphereMix = smoothstep(0.50, 0.72, t);

        if (sphereMix < 0.98) {
          const gChrome = ctx.copy();
          gChrome.opacity = metalBlend * (1.0 - sphereMix);
          const horizonShift = Math.sin(t * 7.0) * 0.05;
          gChrome.fill(
            bodyPath,
            Shading.linearGradient(
              Gradient.stops([
                [chromeBright, 0.0],
                [chromeSilver, 0.24],
                [chromeDark, clamp01(0.47 + horizonShift)],
                [chromeMid, clamp01(0.57 + horizonShift)],
                [chromeBright, 0.80],
                [chromeDark.mix(chromeMid, 0.35), 1.0],
              ]),
              new CGPoint(cx - rx * 0.25, bb.minY),
              new CGPoint(cx + rx * 0.25, bb.maxY)
            )
          );
          drawChromeReflections(ctx, bodyPath, bb.minX, bb.maxX, bb.minY, bb.maxY, t, chromeDark, metalBlend * (1.0 - sphereMix));
        }

        if (sphereMix > 0.02) {
          // Spherical jewel-like mercury radial gradient.
          const maxR = Math.max(rx, ry) * 1.45;
          const hiPt = new CGPoint(cx - rx * 0.30, cy - ry * 0.32);
          const gSphere = ctx.copy();
          gSphere.opacity = metalBlend * sphereMix;
          gSphere.fill(
            bodyPath,
            Shading.radialGradient(
              Gradient.stops([
                [RGBA.white, 0.0],
                [chromeBright, 0.22],
                [chromeSilver, 0.48],
                [chromeDark, 0.78],
                [chromeSilver.alpha(0.92), 1.0],
              ]),
              hiPt,
              0.0,
              maxR
            )
          );
          // Crisp spherical specular highlight dot.
          const sr = Math.max(1.0, rx * 0.24);
          gSphere.fill(
            Path.ellipse(new CGRect(cx - rx * 0.36 - sr * 0.6, cy - ry * 0.36 - sr * 0.45, sr * 1.3, sr * 0.9)),
            Shading.color(RGBA.white.alpha(0.95))
          );
        }

        // Crisp dark metallic rim so mercury reads sharply on white desktops.
        ctx.stroke(bodyPath, Shading.color(chromeDark.alpha(0.62 * metalBlend)), 1.3);
      }

      // Liquefaction sheen sweep (t = 0.00..0.30).
      const sheenP = phase(t, 0.0, 0.30);
      if (sheenP > 0.0 && sheenP < 1.0) {
        const gSheen = ctx.copy();
        gSheen.clip(bodyPath);
        const sheenY = lerp(pad.minY - 30.0, pad.maxY + 30.0, easeInOut(sheenP));
        const sheenAlpha = Math.sin(Math.PI * sheenP) * 0.72;
        gSheen.fill(
          Path.rect(new CGRect(pad.minX - 10.0, sheenY - 38.0, padW + 20.0, 76.0)),
          Shading.linearGradient(
            Gradient.stops([
              [RGBA.white.alpha(0.0), 0.0],
              [chromeBright.alpha(sheenAlpha), 0.42],
              [RGBA.white.alpha(sheenAlpha * 1.15), 0.52],
              [chromeDark.alpha(sheenAlpha * 0.45), 0.68],
              [RGBA.white.alpha(0.0), 1.0],
            ]),
            new CGPoint(pad.midX, sheenY - 38.0),
            new CGPoint(pad.midX, sheenY + 38.0)
          )
        );
      }
    }

    // Detached dripping mercury beads coalescing back into the central bead (t = 0.16..0.82).
    const sDrop = (seed + 503) >>> 0;
    const dropCount = 14;
    for (let i = 0; i < dropCount; i++) {
      const u = 0.12 + closeHash(i, 1, sDrop) * 0.76;
      const startT = 0.15 + closeHash(i, 2, sDrop) * 0.32;
      const lifeLen = 0.28 + closeHash(i, 3, sDrop) * 0.18;
      const life = phase(t, startT, startT + lifeLen);
      if (life <= 0.0 || life >= 1.0) continue;

      const spawnX = pad.minX + u * padW;
      const spawnY = pad.maxY + 12.0 + closeHash(i, 6, sDrop) * 24.0;
      const fallY = spawnY + (16.0 + closeHash(i, 4, sDrop) * 28.0) * Math.sin(Math.PI * Math.min(1.0, life * 1.2));
      const pull = easeInOut(phase(life, 0.24, 1.0));
      const cx = lerp(spawnX, poolX, pull);
      const cy = lerp(fallY, poolY + 4.0, pull);

      const baseR = 3.0 + closeHash(i, 5, sDrop) * 5.8;
      const rx = baseR * (1.0 - 0.65 * easeIn(life));
      const ry = rx * (1.0 + 0.45 * Math.sin(Math.PI * life));
      const alpha = smoothstep(0.0, 0.12, life) * (1.0 - phase(life, 0.84, 1.0));
      drawMercuryBead(ctx, cx, cy, rx, ry, 0.5 * (1.0 - pull), chromeBright, chromeSilver, chromeDark, alpha);
    }

    // Final crisp 4-point chrome specular glint as the last bead vanishes (t = 0.84..0.99).
    const glintLife = phase(t, 0.84, 0.99);
    if (glintLife > 0.0 && glintLife < 1.0) {
      drawStarGlint(ctx, poolX, poolY, Math.sin(Math.PI * glintLife), 20.0, chromeBright);
    }
  }
}
