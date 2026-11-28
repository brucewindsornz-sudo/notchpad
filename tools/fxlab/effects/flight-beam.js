export const kind = 'flight';
export const duration = 1.22;

const navy = new RGBA(0.055, 0.16, 0.39);
const blue = new RGBA(0.15, 0.55, 0.99);
const ice = new RGBA(0.61, 0.96, 1);
const silver = new RGBA(1, 0.98, 0.87);
const pt = (x, y) => new CGPoint(x, y);
const rect = (x, y, w, h) => new CGRect(x, y, w, h);
const ink = c => Shading.color(c);
const line = (p, x, y, ex, ey) => { p.move(pt(x, y)); p.addLine(pt(ex, ey)); };
const halo = (ctx, p, r, c) => {
  const paint = Shading.radialGradient(Gradient.stops([[c, 0], [c.alpha(c.a * 0.32), 0.42], [c.alpha(0), 1]]), p, 0, r);
  ctx.fill(Path.ellipse(rect(p.x - r, p.y - r, r * 2, r * 2)), paint);
};

// In-place dematerialisation, a narrow travelling signal, then a top-down
// exposure of the exact docked image. No card travels between the endpoints.
export function draw(f, ctx) {
  if (f.t <= 0) { f.drawFrom(ctx); return; }
  if (f.t >= 1) { f.drawTo(ctx); return; }
  const tint = blue.mix(f.accent, 0.18);
  const source = pt(f.from.midX, f.from.midY), destination = pt(f.notch.midX, f.notch.maxY - 2);
  if (f.t < 0.51) terminal(f, ctx, false, phase(f.t, 0, 0.51), source, tint);
  if (f.t > 0.49) terminal(f, ctx, true, 1 - phase(f.t, 0.49, 0.994), destination, tint);
  transmission(f, ctx, source, destination, tint);
}

function terminal(f, ctx, landing, q, origin, tint) {
  const r = landing ? f.to : f.from;
  const shape = landing ? f.toPath : f.fromPath;
  const cells = landing ? f.toCells : f.fromCells;
  const seed = (f.seed + (landing ? 2207 : 0)) >>> 0;
  const intact = new Path(), ghost = new Path(), fibres = new Path(), cores = new Path();
  const n = 30, h = r.height / n, lanes = [];
  const drawCard = (g, a = 1) => landing ? f.drawTo(g, null, a) : f.drawFrom(g, null, a);

  // On departure the outside edges dissolve inwards. On arrival the shower
  // travels down from the notch instead, with uneven light at its leading edge.
  for (let i = 0; i < n; i++) {
    const y = r.minY + h * i;
    const n0 = 0.77 * (0.5 + 0.5 * Math.cos((i / n - 0.57) * Math.PI * 2)) + 0.23 * closeHash(i, 15, seed);
    const gone = easeInOut(phase(q, 0.014 + n0 * 0.097, 0.60 + n0 * 0.12));
    if (!landing) {
      const half = r.width * 0.5 * (1 - gone);
      if (half > 0.01) intact.addRect(rect(r.midX - half, y, half * 2, h));
      const edge = Math.min(r.width * 0.5 - half, 7 + n0 * 24);
      if (edge > 0.06) {
        const left = rect(r.midX - half - edge, y, edge, h), right = rect(r.midX + half, y, edge, h);
        ghost.addRect(left); ghost.addRect(right);
        lanes.push(left, right);
      }
    } else {
      const x = r.minX + i * r.width / n, w = r.width / n;
      const remain = r.height * (1 - gone);
      if (remain > 0.01) intact.addRect(rect(x, r.minY, w, remain));
      const edge = Math.min(r.height - remain, 14 + n0 * 32);
      if (edge > 0.06) {
        const lane = rect(x, r.minY + remain, w, edge);
        ghost.addRect(lane);
        lanes.push(lane);
      }
    }
  }
  if (!intact.isEmpty) {
    const g = ctx.copy();
    g.clip(intact);
    drawCard(g);
  }
  const glow = smoothstep(0.01, 0.21, q) * (1 - smoothstep(0.55, 0.89, q));
  if (!ghost.isEmpty && glow > 0) {
    const g = ctx.copy();
    g.clip(shape); g.clip(ghost);
    drawCard(g, 0.19 * glow);
    const paint = Gradient.stops([[tint.alpha(0.53 * glow), 0], [ice.alpha(0.29 * glow), 0.19], [tint.alpha(0), 1]]);
    for (let i = 0; i < lanes.length; i++) {
      const a = lanes[i];
      const start = landing ? pt(a.minX, a.minY) : pt(i % 2 === 0 ? a.maxX : a.minX, a.minY);
      const end = landing ? pt(a.minX, a.maxY) : pt(i % 2 === 0 ? a.minX : a.maxX, a.minY);
      g.fill(Path.rect(a), Shading.linearGradient(paint, start, end));
    }
  }
  const dissolve = smoothstep(0.13, 0.86, q);
  const bloom = smoothstep(0.4, 0.72, q) * (1 - smoothstep(0.78, 0.96, q));
  if (bloom > 0) {
    const y = landing ? origin.y - 21 : origin.y - r.height * 0.3;
    const height = r.height * 0.61 * (1 - 0.6 * dissolve);
    const w = lerp(44, 7, dissolve);
    const cross = Gradient.stops([[tint.alpha(0), 0], [tint.alpha(0.50 * bloom), 0.39],
      [ice.alpha(0.71 * bloom), 0.5], [tint.alpha(0.50 * bloom), 0.61], [tint.alpha(0), 1]]);
    ctx.fill(Path.ellipse(rect(origin.x - w, y, 2 * w, height)),
      Shading.linearGradient(cross, pt(origin.x - w, y), pt(origin.x + w, y)));
  }
  const ax = Math.min(71, r.width * 0.17);
  for (let i = 0; i < 38; i++) {
    const x0 = closeHash(i, 28, seed), u = closeHash(i, 29, seed), v = closeHash(i, 30, seed);
    const x = lerp(r.minX + r.width * x0, origin.x + (x0 - 0.5) * ax, dissolve);
    const y = lerp(r.minY + r.height * u, origin.y, dissolve);
    const len = (13 + (v * v) * (r.height * 0.45)) * (0.45 + 0.55 * Math.sin(Math.PI * q));
    line(fibres, x, y - len * 0.50, x, y + len * 0.72);
    if (i % 3 !== 0) line(cores, x + 0.6, y - len * 0.28, x + 0.6, y + len * 0.44);
  }
  ctx.stroke(fibres, ink(navy.alpha(glow * 0.28)), 4.2);
  ctx.stroke(fibres, ink(tint.alpha(glow * 0.71)), 2.35);
  ctx.stroke(cores, ink(ice.alpha(glow * 0.92)), 0.95);

  const spray = new Path();
  for (let i = 0; i < 162; i++) {
    const u = closeHash(i, 70, seed), v = closeHash(i, 71, seed);
    const tintCell = cells.color(Math.floor(u * cells.cols), Math.floor(v * cells.rows));
    if (tintCell.a < 0.18) continue;
    const k = closeHash(i, 72, seed), d = closeHash(i, 73, seed);
    const age = phase(q, 0.05 + 0.26 * k, 0.76 + d * 0.22);
    if (age <= 0 || age >= 1) continue;
    const gather = smoothstep(0.08, 0.97, age);
    const angle = (u + age * (0.54 + 0.52 * d)) * Math.PI * 2;
    const swirl = Math.sin(Math.PI * age) * (17 + 33 * k);
    const x = lerp(r.minX + r.width * u, origin.x, gather) + Math.sin(angle) * swirl;
    const y = lerp(r.minY + r.height * v, origin.y, gather) - swirl * 0.63;
    const flicker = 0.37 + 0.63 * Math.pow(0.5 + 0.5 * Math.sin(angle * 4 + d * 8), 3);
    const a = smoothstep(0, 0.20, age) * (1 - smoothstep(0.68, 1, age)) * flicker;
    const s = (0.63 + k * 1.28) * (1 - 0.56 * gather);
    const c = tintCell.mix(i % 8 === 0 ? silver : ice, 0.76 + 0.22 * d);
    ctx.fill(Path.ellipse(rect(x - s, y - s * 1.4, s * 2, s * 2.8)), ink(c.alpha(a)));
    if (i % 6 === 0 && a > 0.48) {
      line(spray, x, y - s * 3.4, x, y + s * 3.4);
      line(spray, x - s * 1.5, y, x + s * 1.5, y);
    }
  }
  ctx.stroke(spray, ink(silver.alpha(glow * 0.83)), 0.95);
  const flare = smoothstep(0.60, 0.83, q) * (1 - smoothstep(0.88, 1, q));
  if (flare > 0) halo(ctx, origin, 46 * flare + 12, tint.alpha(0.83 * flare));
}

function transmission(f, ctx, source, dest, tint) {
  if (f.t <= 0.31 || f.t >= 0.68) return;
  const q = phase(f.t, 0.31, 0.68);
  const dx = dest.x - source.x, dy = dest.y - source.y;
  const fullLen = Math.hypot(dx, dy);
  const nx = -dy / Math.max(1, fullLen), ny = dx / Math.max(1, fullLen);
  const spread = Math.min(12, fullLen * 0.09);
  const head = easeInOut(phase(q, 0, 0.73));
  const tail = easeInOut(phase(q, 0.21, 1));
  const strength = smoothstep(0, 0.18, q) * (1 - smoothstep(0.75, 1, q));
  const centre = u => pt(lerp(source.x, dest.x, u), lerp(source.y, dest.y, u));
  const ray = new Path();
  ray.move(centre(tail)); ray.addLine(centre(head));
  // A quiet indigo body survives on light walls; the white core reads on dark ones.
  ctx.stroke(ray, ink(navy.alpha(strength * 0.34)), { lineWidth: 14, lineCap: 'round' });
  ctx.stroke(ray, ink(tint.alpha(strength * 0.38)), { lineWidth: 7.8, lineCap: 'round' });
  ctx.stroke(ray, ink(ice.alpha(strength * 0.87)), { lineWidth: 2.2, lineCap: 'round' });
  for (let i = 0; i < 2; i++) {
    const p = new Path();
    for (let j = 0; j <= 28; j++) {
      const v = j / 28, u = lerp(tail, head, v);
      const c = centre(u);
      const wave = Math.sin(u * 25 - q * 9 + Math.PI * i) * Math.sin(Math.PI * v) * spread;
      const s = pt(c.x + nx * wave, c.y + ny * wave);
      if (j === 0) p.move(s); else p.addLine(s);
    }
    ctx.stroke(p, ink((i === 0 ? tint : ice).alpha(strength * 0.57)), 1.17);
  }
  const tip = centre(head);
  const pulse = strength * (1 - 0.38 * smoothstep(0.65, 1, q));
  halo(ctx, tip, 18 + 27 * pulse, tint.alpha(pulse * 0.79));
  const star = new Path(), core = new Path();
  const hx = 8 + 18 * pulse;
  line(star, tip.x - hx, tip.y, tip.x + hx, tip.y);
  line(star, tip.x, tip.y - hx * 0.74, tip.x, tip.y + hx * 0.74);
  const bend = 2.6 + 6.4 * pulse;
  line(core, tip.x - bend, tip.y, tip.x + bend, tip.y);
  line(core, tip.x, tip.y - bend * 0.65, tip.x, tip.y + bend * 0.65);
  ctx.stroke(star, ink(navy.alpha(pulse * 0.38)), 2.8);
  ctx.stroke(star, ink(ice.alpha(pulse * 0.84)), 1.15);
  ctx.stroke(core, ink(silver.alpha(pulse)), 1.8);
}
