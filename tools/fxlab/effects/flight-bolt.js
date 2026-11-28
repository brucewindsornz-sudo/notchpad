export const kind = 'flight';
export const duration = 1.07;

function point(a, b, u) {
  return new CGPoint(lerp(a.x, b.x, u), lerp(a.y, b.y, u));
}

function route(a, b, count, amplitude, salt, seed, bow = 0) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const length = Math.max(1, Math.hypot(dx, dy));
  const points = [a];
  for (let i = 1; i < count; i++) {
    const u = i / count;
    const coarse = closeNoise(u * 7.1, salt, seed) - 0.5;
    const rough = closeHash(i, salt + 13, seed) - 0.5;
    const edge = Math.sin(Math.PI * u);
    const cross = (bow + amplitude * (coarse * 1.45 + rough * 0.7)) * edge;
    const p = point(a, b, u);
    points.push(new CGPoint(p.x - dy * cross / length, p.y + dx * cross / length));
  }
  points.push(b);
  return points;
}

function trace(path, points, first, last) {
  if (last <= first) return;
  const a = first * (points.length - 1), b = last * (points.length - 1);
  const i = Math.floor(a), j = Math.floor(b);
  path.move(point(points[i], points[i + 1], a - i));
  for (let k = i + 1; k <= j; k++) path.addLine(points[k]);
  if (j < points.length - 1) path.addLine(point(points[j], points[j + 1], b - j));
}

function sample(points, u) {
  const x = clamp01(u) * (points.length - 1);
  const i = Math.min(points.length - 2, Math.floor(x));
  return point(points[i], points[i + 1], x - i);
}

function filament(ctx, path, ink, intensity, width) {
  if (intensity <= 0 || path.isEmpty) return;
  const line = (w) => ({lineWidth: w, lineCap: 'round', lineJoin: 'round'});
  ctx.stroke(path, Shading.color(ink.alpha(0.13 * intensity)), line(width * 7));
  ctx.stroke(path, Shading.color(ink.alpha(0.76 * intensity)), line(width * 2.5));
  const core = ctx.copy();
  core.blendMode = 'plusLighter';
  core.stroke(path, Shading.color(ink.mix(RGBA.white, 0.91).alpha(intensity)), line(width));
}

function bloom(ctx, p, r, ink, intensity) {
  if (intensity <= 0) return;
  const colours = Gradient.stops([[RGBA.white.alpha(intensity * 0.9), 0],
    [ink.mix(RGBA.white, 0.46).alpha(intensity * 0.63), 0.14],
    [ink.alpha(intensity * 0.22), 0.42], [ink.alpha(0), 1]]);
  ctx.fill(Path.ellipse(new CGRect(p.x - r, p.y - r, r * 2, r * 2)),
    Shading.radialGradient(colours, p, 0, r));
}

export function draw(f, ctx) {
  const t = f.t;
  if (t <= 0) { f.drawFrom(ctx); return; }
  if (t >= 1) { f.drawTo(ctx); return; }
  const src = f.from, dst = f.to;
  const ink = new RGBA(0.30, 0.10, 0.78).mix(f.accent, 0.20);
  const iris = new RGBA(0.64, 0.53, 1).mix(f.accent, 0.15);
  const latch = new CGPoint(f.notch.midX, Math.max(3, f.notch.maxY - 1));
  const dx = latch.x - src.midX, dy = latch.y - src.midY;
  const distance = Math.max(1, Math.hypot(dx, dy));
  const nx = dx / distance, ny = dy / distance;
  const offset = Math.min(95, src.width * 0.18, src.height * 0.29, distance * 0.27);
  const focus = new CGPoint(src.midX + nx * offset, src.midY + ny * offset);
  // The floating image pinches into the leader; the rows are original image, not coloured blocks.
  if (t < 0.38) {
    if (t <= 0.045) f.drawFrom(ctx);
    else {
      const bands = 13, band = src.height / bands;
      for (let i = 0; i < bands; i++) {
        const y = src.minY + band * i, mid = y + band * 0.5;
        const skew = 0.044 * closeHash(i, 37, f.seed);
        const tuck = smoothstep(0.047 + skew, 0.385 - skew, t);
        const fade = 1 - smoothstep(0.245 + skew, 0.377, t);
        const wy = lerp(1, 0.03, tuck), wx = lerp(1, 0.022, tuck);
        const xShift = (focus.x - src.midX) * tuck;
        const targetY = lerp(mid, focus.y, tuck) + Math.sin(i * 1.91) * Math.sin(Math.PI * tuck) * 11;
        const g = ctx.copy();
        g.translateBy(src.midX + xShift, targetY);
        g.scaleBy(wx, wy);
        g.translateBy(-src.midX, -mid);
        g.clip(Path.rect(new CGRect(src.minX - 1, y - 0.24, src.width + 2, band + 0.48)));
        f.drawFrom(g, null, fade);
      }
    }
    const charge = smoothstep(0.015, 0.115, t) * (1 - smoothstep(0.31, 0.40, t));
    const forks = new Path();
    const gather = smoothstep(0.07, 0.37, t);
    for (let i = 0; i < 6; i++) {
      const angle = (i / 6) * Math.PI * 2 + 0.2;
      const start = new CGPoint(src.midX + Math.cos(angle) * src.width * 0.43,
        src.midY + Math.sin(angle) * src.height * 0.42);
      const head = point(start, focus, gather * 0.87);
      const branch = route(head, focus, 9, lerp(34, 12, gather), 60 + i * 3, f.seed);
      trace(forks, branch, 0.09, easeOut(phase(t, 0.019 + i * 0.012, 0.19 + i * 0.012)));
    }
    filament(ctx, forks, ink, charge * 0.73, 0.98);
    bloom(ctx, focus, lerp(36, 73, gather), iris, charge * gather * 0.88);
  }
  const stemLength = Math.hypot(latch.x - focus.x, latch.y - focus.y);
  const count = Math.max(14, Math.min(51, Math.round(stemLength / 16)));
  const bow = Math.min(70, stemLength * 0.17) * (dx < -40 ? -1 : 1);
  const trunk = route(focus, latch, count, Math.min(115, stemLength * 0.42 + 13), 24, f.seed, bow);
  // The luminous head travels along the ionised path before the strong return stroke.
  const travel = smoothstep(0.24, 0.63, t);
  const retreat = easeIn(phase(t, 0.57, 0.81));
  const arrival = smoothstep(0.55, 0.625, t) * (1 - smoothstep(0.64, 0.748, t));
  const feeler = smoothstep(0.45, 0.60, t) * (1 - smoothstep(0.61, 0.665, t));
  if (feeler > 0) {
    const upstream = new Path(), twig = new Path();
    const q = smoothstep(0.44, 0.618, t);
    trace(upstream, trunk, 1 - 0.25 * q, 1);
    const origin = sample(trunk, 0.96);
    const end = new CGPoint(origin.x - nx * 22 + ny * 26, Math.max(3, origin.y - ny * 22 - nx * 26));
    trace(twig, route(origin, end, 5, 9, 151, f.seed), 0, q);
    filament(ctx, upstream, iris, feeler * 0.66, 1.25);
    filament(ctx, twig, ink, feeler * 0.55, 0.78);
  }
  if (travel > 0 && retreat < 1) {
    const path = new Path(), head = new Path(), branches = new Path();
    trace(path, trunk, retreat, travel);
    trace(head, trunk, Math.max(retreat, travel - 0.26), travel);
    for (let j = 0; j < 8; j++) {
      const u = 0.13 + j * 0.095;
      const k = Math.round(u * count);
      if (retreat >= u || travel <= u || k >= count) continue;
      const origin = trunk[k], side = j % 2 === 0 ? 1 : -1;
      const reach = Math.min(96, stemLength * 0.42 + 15) * (0.52 + 0.47 * closeHash(j, 71, f.seed));
      const drift = Math.min(102, stemLength * 0.20) * (0.68 + 0.4 * closeHash(j, 7, f.seed));
      const tip = new CGPoint(origin.x + nx * drift - ny * reach * side,
        Math.max(3, origin.y + ny * drift + nx * reach * side));
      const branch = route(origin, tip, 8, 22, 72 + j, f.seed);
      const growing = smoothstep(u, u + 0.17, travel);
      trace(branches, branch, 0, growing);
      if (j % 3 === 1) {
        const split = branch[4];
        const end = new CGPoint(split.x + nx * drift * 0.46 + ny * side * reach * 0.26,
          Math.max(3, split.y + ny * drift * 0.46 - nx * side * reach * 0.26));
        trace(branches, route(split, end, 5, 11, 105 + j, f.seed), 0, smoothstep(0.42, 0.95, growing));
      }
    }
    const live = (1 - smoothstep(0.67, 0.81, t)) * smoothstep(0.245, 0.32, t);
    filament(ctx, branches, ink, live * (0.57 + 0.26 * arrival), 1.02);
    filament(ctx, path, ink, live * (0.52 + 0.46 * arrival), 1.55 + arrival * 1.42);
    filament(ctx, head, iris, live * 0.92, 2.15);
    bloom(ctx, sample(trunk, travel), 34, iris, live * (0.61 + 0.30 * arrival));
  }
  // Docking: a ragged front writes the real notch-shaped image back from the point of contact.
  const reveal = smoothstep(0.555, 0.848, t);
  if (reveal >= 1) f.drawTo(ctx);
  if (reveal > 0 && reveal < 1) {
    const mask = new Path(), seam = new Path();
    mask.move(new CGPoint(dst.minX - 1, dst.minY - 2));
    mask.addLine(new CGPoint(dst.maxX + 1, dst.minY - 2));
    for (let i = 26; i >= 0; i--) {
      const u = i / 26;
      const uneven = (closeHash(i, 116, f.seed) - 0.5) * 14;
      const arch = 45 * (1 - 4 * (u - 0.5) * (u - 0.5));
      const y = dst.minY + reveal * (dst.height + 3) + (arch + uneven) * Math.sin(Math.PI * reveal);
      const p = new CGPoint(lerp(dst.minX - 1, dst.maxX + 1, u), y);
      mask.addLine(p);
      if (i === 26) seam.move(p); else seam.addLine(p);
    }
    mask.closeSubpath();
    const g = ctx.copy();
    g.clip(f.toPath);
    const snapshot = g.copy();
    snapshot.clip(mask);
    f.drawTo(snapshot);
    const seamPower = smoothstep(0, 0.11, reveal) * (1 - smoothstep(0.68, 0.99, reveal));
    filament(g, seam, ink, seamPower * 0.75, 1.36);
  }
  if (arrival > 0) {
    const g = ctx.copy();
    g.clip(f.toPath);
    bloom(g, latch, Math.min(235, dst.width * 0.49), iris, arrival * 0.68);
  }
  bloom(ctx, latch, 65, iris, arrival * 0.86);
  const tail = smoothstep(0.62, 0.69, t) * (1 - smoothstep(0.743, 0.956, t));
  if (tail <= 0) return;
  const residual = new Path();
  for (let i = 0; i < 5; i++) {
    const sign = i % 2 === 0 ? -1 : 1;
    const u = easeOut(phase(t, 0.62 + i * 0.010, 0.85 + i * 0.015));
    const end = new CGPoint(latch.x + sign * dst.width * (0.05 + 0.037 * i) * u,
      latch.y + dst.height * (0.08 + 0.045 * i) * u);
    trace(residual, route(latch, end, 8, 19 * u, 120 + i, f.seed),
      smoothstep(0.76, 0.95, t) * 0.82, u);
  }
  filament(ctx, residual, ink, tail * 0.72, 0.98);
  const rng = new CloseRNG(f.seed ^ 0x44B1);
  for (let i = 0; i < 37; i++) {
    const angle = rng.range(-0.12, Math.PI + 0.12), speed = rng.range(30, 144);
    const start = rng.range(0.59, 0.69), length = rng.range(2.1, 9);
    const span = rng.range(0.12, 0.28);
    const life = phase(t, start, start + span);
    if (life <= 0 || life >= 1) continue;
    const x = latch.x + Math.cos(angle) * speed * easeOut(life);
    const y = latch.y + Math.sin(angle) * speed * easeOut(life) + 15 * life * life;
    const l = length * (1 - 0.73 * life);
    const line = new Path();
    line.move(new CGPoint(x - Math.cos(angle) * l, y - Math.sin(angle) * l));
    line.addLine(new CGPoint(x, y));
    ctx.stroke(line, Shading.color((i % 4 === 0 ? RGBA.white : iris).alpha(
      0.75 * (1 - life) * smoothstep(0, 0.16, life))), i % 4 === 0 ? 1.4 : 0.94);
  }
}
