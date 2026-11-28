export const kind = 'close';
export const duration = 0.98;

function point(a, b, u) {
  return new CGPoint(lerp(a.x, b.x, u), lerp(a.y, b.y, u));
}

function channel(a, b, steps, width, salt, seed) {
  const length = Math.max(1, Math.hypot(b.x - a.x, b.y - a.y));
  const nx = -(b.y - a.y) / length, ny = (b.x - a.x) / length;
  const points = [a];
  for (let i = 1; i < steps; i++) {
    const u = i / steps;
    const p = point(a, b, u);
    const coarse = (closeNoise(u * 6, salt, seed) - 0.5) * 1.2;
    const fine = closeHash(i, salt, seed) - 0.5;
    const d = width * Math.sin(Math.PI * u) * (coarse + fine);
    points.push(new CGPoint(p.x + nx * d, p.y + ny * d));
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

function tube(ctx, path, ink, intensity, width) {
  if (intensity <= 0 || path.isEmpty) return;
  const line = (w) => ({lineWidth: w, lineCap: 'round', lineJoin: 'round'});
  ctx.stroke(path, Shading.color(ink.alpha(0.16 * intensity)), line(width * 6));
  ctx.stroke(path, Shading.color(ink.alpha(0.65 * intensity)), line(width * 2.6));
  const hot = ctx.copy();
  hot.blendMode = 'plusLighter';
  hot.stroke(path, Shading.color(ink.mix(RGBA.white, 0.86).alpha(intensity)), line(width));
}

function halo(ctx, p, r, ink, intensity) {
  if (intensity <= 0) return;
  const shape = Path.ellipse(new CGRect(p.x - r, p.y - r, r * 2, r * 2));
  const colours = Gradient.stops([[RGBA.white.alpha(intensity * 0.75), 0],
    [ink.mix(RGBA.white, 0.45).alpha(intensity * 0.45), 0.15],
    [ink.alpha(intensity * 0.11), 0.54], [ink.alpha(0), 1]]);
  ctx.fill(shape, Shading.radialGradient(colours, p, 0, r));
}

function rimPoint(pad, side, u, inset) {
  const x = side < 0 ? pad.minX + inset : pad.maxX - inset;
  const s = 1 - Math.abs(2 * u - 1);
  return new CGPoint(x + side * 6 * s, lerp(pad.minY + 25, pad.maxY - 15, u));
}

export function draw(f, ctx) {
  const t = f.t, r = f.pad;
  if (t <= 0) { f.drawPad(ctx); return; }
  if (t >= 1) return;
  const ink = new RGBA(0.16, 0.29, 0.91).mix(f.accent, 0.16);
  const hot = new RGBA(0.49, 0.73, 1).mix(f.accent, 0.12);
  const impact = new CGPoint(r.minX + r.width * 0.44, r.minY + r.height * 0.56);
  const entry = f.floating ? new CGPoint(r.midX + r.width * 0.19, r.minY - Math.min(71, r.height * 0.3))
    : new CGPoint(f.target.x, Math.max(2, f.sink.maxY - 2));
  const main = channel(entry, impact, 17, Math.min(88, r.width * 0.23), 19, f.seed);
  const burned = smoothstep(0.28, 0.76, t);
  const radius = 2.02 * burned;
  const rx = r.width * 0.49, ry = r.height * 0.50;
  const ring = new Path();
  const teeth = [];
  if (radius > 0) {
    for (let i = 0; i < 64; i++) {
      const a = (i / 64) * Math.PI * 2;
      const tooth = 0.92 + 0.14 * closeHash(i, 94, f.seed) + 0.09 * Math.sin(5 * a + 0.6);
      const p = new CGPoint(impact.x + Math.cos(a) * rx * radius * tooth,
        impact.y + Math.sin(a) * ry * radius * tooth);
      teeth.push(p);
      if (i === 0) ring.move(p); else ring.addLine(p);
    }
    ring.closeSubpath();
  }
  // The photograph remains still. The hot channel punches a hole through the actual note.
  if (t < 0.77) {
    const image = ctx.copy();
    if (radius > 0) image.clip(ring, {inverse: true});
    f.drawPad(image);
  }
  const flash = smoothstep(0.125, 0.169, t) * (1 - smoothstep(0.173, 0.278, t));
  const echo = 0.25 * smoothstep(0.242, 0.275, t) * (1 - smoothstep(0.281, 0.385, t));
  const inside = ctx.copy();
  inside.clip(f.padPath);
  halo(inside, impact, Math.min(240, r.width * 0.53), hot, 0.75 * flash + echo);
  if (flash > 0) {
    const g = inside.copy();
    g.blendMode = 'plusLighter';
    g.fill(f.padPath, Shading.color(hot.alpha(flash * (f.dark ? 0.25 : 0.12))));
  }
  // Two asymmetric leaders travel across the note, then scramble around the sidewalls.
  const spread = easeOut(phase(t, 0.155, 0.43));
  const sideGlow = smoothstep(0.14, 0.205, t) * (1 - smoothstep(0.37, 0.65, t));
  if (sideGlow > 0) {
    const forks = new Path(), walls = new Path();
    const inset = f.floating ? 7 : 15;
    for (const side of [-1, 1]) {
      const junction = rimPoint(r, side, side < 0 ? 0.37 : 0.68, inset);
      const arm = channel(impact, junction, 17, r.height * 0.32, side + 72, f.seed);
      trace(forks, arm, 0, spread);
      for (const end of [0, 1]) {
        const rim = channel(junction, rimPoint(r, side, end, inset), 10, 15, side + end * 5 + 92, f.seed);
        trace(walls, rim, 0, easeOut(phase(t, 0.25, 0.52)));
      }
      for (let j = 0; j < 3; j++) {
        const k = 3 + j * 4;
        const root = arm[k];
        const dest = new CGPoint(root.x + side * r.width * (0.07 + 0.028 * j),
          root.y + r.height * (j % 2 === 0 ? -0.19 : 0.16));
        const branch = channel(root, dest, 7, 18, 38 + j * 5 + side, f.seed);
        trace(forks, branch, 0, easeOut(phase(t, 0.235 + k * 0.008, 0.44 + k * 0.007)));
      }
    }
    if (radius > 0) inside.clip(ring, {inverse: true});
    tube(inside, walls, ink, sideGlow * 0.88, 1.45);
    tube(inside, forks, ink, sideGlow * 0.79, 1.1);
  }
  if (t > 0.28 && t < 0.77) {
    const edge = ctx.copy();
    edge.clip(f.padPath);
    const strength = smoothstep(0.28, 0.35, t) * (1 - smoothstep(0.60, 0.77, t));
    const broken = new Path(), streamers = new Path();
    for (let i = 0; i < teeth.length; i++) {
      const charge = closeNoise(i * 0.12, t * 5, f.seed ^ 0xD151);
      if (charge < 0.37) continue;
      broken.move(teeth[i]);
      broken.addLine(teeth[(i + 1) % teeth.length]);
      if (i % 6 === 1 && i < teeth.length - 1) {
        const twig = point(teeth[i], impact, 0.045 + 0.12 * charge);
        streamers.move(teeth[i + 1]);
        streamers.addLine(point(teeth[i], twig, 0.59));
        streamers.addLine(twig);
      }
    }
    edge.stroke(ring, Shading.color(ink.alpha(strength * 0.31)), 4);
    tube(edge, broken, hot, strength * 0.88, 1.05);
    tube(edge, streamers, ink, strength * 0.60, 0.81);
  }
  const leader = easeOut(phase(t, 0.036, 0.163));
  const retreat = easeIn(phase(t, 0.40, 0.88));
  const trunk = new Path(), twigs = new Path();
  trace(trunk, main, 0, leader * (1 - retreat));
  if (t < 0.47) {
    for (let j = 0; j < 5; j++) {
      const k = 3 + j * 2, origin = main[k], side = j % 2 === 0 ? -1 : 1;
      const dest = new CGPoint(origin.x + r.width * (0.08 + j * 0.012) * side,
        origin.y + Math.min(r.height * 0.22, 63) * (0.68 + 0.12 * j));
      const branch = channel(origin, dest, 8, 19, 56 + j, f.seed);
      trace(twigs, branch, 0, easeOut(phase(t, 0.057 + j * 0.013, 0.16 + j * 0.014)));
    }
  }
  const energy = smoothstep(0.039, 0.136, t) * (1 - smoothstep(0.29, 0.87, t));
  const current = 0.27 + 0.17 * closeNoise(t * 24, 13, f.seed);
  tube(ctx, twigs, ink, Math.min(1, flash * 0.69 + echo + energy * 0.36) *
    (1 - smoothstep(0.26, 0.46, t)), 0.96);
  tube(ctx, trunk, ink, Math.min(1, flash + echo + energy * current), 1.65 + flash * 1.46);
  // Chip colours come from the consumed note. Stretch them into short, cooling filaments.
  const embers = new CloseRNG(f.seed ^ 0xAE71);
  for (let i = 0; i < 108; i++) {
    const col = embers.int(f.cells.cols), row = embers.int(f.cells.rows);
    const angle = embers.range(-Math.PI, Math.PI), speed = embers.range(21, 115);
    const length = embers.range(1.9, 11), span = embers.range(0.18, 0.34);
    const cell = f.cells.rect(col, row);
    const radial = Math.hypot((cell.midX - impact.x) / rx, (cell.midY - impact.y) / ry);
    const start = lerp(0.29, 0.70, Math.pow(clamp01(radial / 1.57), 0.75));
    const life = phase(t, start, Math.min(0.963, start + span));
    if (life <= 0 || life >= 1) continue;
    const c = f.cells.color(col, row);
    if (c.a < 0.23) continue;
    const push = easeOut(life) * speed;
    const x = cell.midX + Math.cos(angle) * push;
    const y = cell.midY + Math.sin(angle) * push + 28 * life * life;
    const l = length * (1 - 0.77 * life);
    const p = new Path();
    p.move(new CGPoint(x - Math.cos(angle) * l, y - Math.sin(angle) * l));
    p.addLine(new CGPoint(x, y));
    const opacity = (1 - life) * smoothstep(0, 0.14, life);
    const spark = c.mix(i % 6 === 0 ? new RGBA(0.99, 0.59, 0.36) : hot, 0.86);
    ctx.stroke(p, Shading.color(ink.alpha(0.33 * opacity)), i % 6 === 0 ? 3 : 2.05);
    ctx.stroke(p, Shading.color(spark.alpha(0.91 * opacity)), i % 6 === 0 ? 1.7 : 1.15);
    if (i % 3 === 0) ctx.fill(Path.ellipse(new CGRect(x - 0.7, y - 0.7, 1.4, 1.4)),
      Shading.color(RGBA.white.alpha(opacity * 0.85)));
  }
  const after = smoothstep(0.42, 0.55, t) * (1 - smoothstep(0.64, 0.88, t));
  if (after > 0) ctx.stroke(f.padPath, Shading.color(ink.alpha(after * 0.22)), 1.0);
  const sink = f.floating ? f.target : entry;
  if (f.floating) {
    const closing = easeInOut(phase(t, 0.62, 0.89));
    const tail = channel(impact, sink, 7, 13, 94, f.seed);
    const residual = new Path();
    trace(residual, tail, 0.72 * closing, easeOut(phase(t, 0.52, 0.73)));
    tube(ctx, residual, ink, 0.42 * smoothstep(0.52, 0.64, t) * (1 - smoothstep(0.82, 0.94, t)), 1.2);
  }
  const last = smoothstep(0.71, 0.825, t) * (1 - smoothstep(0.84, 0.975, t));
  halo(ctx, sink, 25, ink, last * 0.56);
  const pin = new Path();
  pin.move(new CGPoint(sink.x - 8 * last, sink.y));
  pin.addLine(new CGPoint(sink.x + 8 * last, sink.y));
  tube(ctx, pin, ink, last * 0.72, 1.2);
}
