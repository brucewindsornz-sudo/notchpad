export const kind = 'close';
export const duration = 1.04;

const navy = new RGBA(0.08, 0.20, 0.46);
const blue = new RGBA(0.18, 0.57, 0.99);
const ice = new RGBA(0.56, 0.94, 1);
const cream = new RGBA(1, 0.91, 0.67);
const ink = c => Shading.color(c);
const point = (x, y) => new CGPoint(x, y);
const rect = (x, y, w, h) => new CGRect(x, y, w, h);
const line = (p, x, y, ex, ey) => { p.move(point(x, y)); p.addLine(point(ex, ey)); };
const radial = (ctx, x, y, r, c) => {
  const p = point(x, y);
  ctx.fill(Path.ellipse(rect(x - r, y - r, r * 2, r * 2)),
    Shading.radialGradient(Gradient.stops([[c, 0], [c.alpha(c.a * 0.38), 0.35], [c.alpha(0), 1]]), p, 0, r));
};

// Charge the lower edge; peel the picture away in offset vertical lanes; orbit the
// released light inwards; snap its residual column shut; leave one optical glint.
export function draw(f, ctx) {
  const t = f.t;
  if (t <= 0) { f.drawPad(ctx); return; }
  if (t >= 1) return;
  const r = f.pad;
  const tx = f.target.x, ty = f.floating ? f.target.y : Math.max(f.target.y, f.sink.maxY - 2);
  const tint = blue.mix(f.accent, 0.21);
  const bright = ice.mix(f.text, f.dark ? 0.14 : 0.03);
  curtain(f, ctx, tint, bright);
  coils(f, ctx, tx, ty, tint);
  glitter(f, ctx, tx, ty, tint, bright);

  const shaft = smoothstep(0.42, 0.66, t) * (1 - smoothstep(0.78, 0.92, t));
  if (shaft > 0) {
    const pinch = smoothstep(0.60, 0.90, t);
    const length = lerp(r.height * (f.floating ? 0.71 : 0.84), 4, pinch);
    const w = lerp(23, 1.5, pinch);
    const y = f.floating ? ty - length * 0.49 : ty - 4;
    const x0 = point(tx - w, y), x1 = point(tx + w, y);
    ctx.fill(Path.ellipse(rect(tx - w, y, 2 * w, length)),
      Shading.linearGradient(Gradient.stops([[tint.alpha(0), 0], [tint.alpha(0.42 * shaft), 0.35],
        [bright.alpha(0.79 * shaft), 0.5], [tint.alpha(0.42 * shaft), 0.65], [tint.alpha(0), 1]]), x0, x1));
    const l = new Path();
    line(l, tx, y + length * 0.12, tx, y + length * 0.89);
    ctx.stroke(l, ink(navy.alpha(0.53 * shaft)), 2.4);
    const add = ctx.copy();
    add.blendMode = 'plusLighter';
    add.stroke(l, ink(bright.alpha(0.83 * shaft)), 1.1);
  }
  const flash = smoothstep(0.75, 0.82, t) * (1 - smoothstep(0.83, 0.99, t));
  if (flash > 0) {
    radial(ctx, tx, ty, 34 * flash + 8, tint.alpha(flash * 0.86));
    const x = lerp(11, 45, easeOut(phase(t, 0.78, 0.92)));
    const l = new Path(), core = new Path();
    line(l, tx - x, ty, tx + x, ty);
    line(core, tx - x * 0.37, ty, tx + x * 0.37, ty);
    line(core, tx, ty - x * 0.22, tx, ty + x * 0.22);
    ctx.stroke(l, ink(navy.alpha(0.64 * flash)), 2.7);
    ctx.stroke(l, ink(ice.alpha(0.84 * flash)), 1.3);
    ctx.stroke(core, ink(RGBA.white.alpha(flash)), 1.6);
  }
}

function curtain(f, ctx, tint, bright) {
  if (f.t >= 0.59) return;
  const r = f.pad, t = f.t, n = 21, w = r.width / n;
  const intact = new Path(), echo = new Path(), light = new Path(), ribbons = new Path();
  const lanes = [];
  for (let i = 0; i < n; i++) {
    const x = r.minX + w * i;
    const q = closeHash(i, 52, f.seed);
    const bow = 0.5 + 0.5 * Math.cos((i / n - 0.61) * Math.PI * 2);
    const u = smoothstep(0.018 + bow * 0.039 + q * 0.017, 0.43 + bow * 0.08 + q * 0.035, t);
    const sweep = r.height * easeOut(u);
    const y = r.maxY - sweep;
    const length = Math.sin(Math.PI * u) * (12 + 31 * q);
    if (y > r.minY) intact.addRect(rect(x, r.minY, w, y - r.minY));
    if (length <= 0.05) continue;
    const edge = rect(x, y, w, Math.min(sweep, 21 + 30 * q));
    echo.addRect(edge);
    lanes.push(edge);
    line(light, x + w * (0.28 + 0.31 * q), y - length, x + w * (0.28 + 0.31 * q), y + length * (0.8 + q));
    line(ribbons, x + w * (0.48 + 0.31 * q), y - length * 0.46, x + w * (0.48 + 0.31 * q), y + length * 2.5);
  }
  if (!intact.isEmpty) {
    const solid = ctx.copy();
    solid.clip(intact);
    f.drawPad(solid);
  }
  if (echo.isEmpty) return;
  const glow = smoothstep(0.024, 0.09, t) * (1 - smoothstep(0.37, 0.58, t));
  const ghost = ctx.copy();
  ghost.clip(f.padPath);
  ghost.clip(echo);
  f.drawPad(ghost, null, 0.20 * glow);
  const veil = Gradient.stops([[tint.alpha(0.46 * glow), 0], [bright.alpha(0.28 * glow), 0.18], [tint.alpha(0), 1]]);
  for (const lane of lanes) {
    ghost.fill(Path.rect(lane), Shading.linearGradient(veil, point(lane.minX, lane.minY), point(lane.minX, lane.maxY)));
  }
  ctx.stroke(ribbons, ink(navy.alpha(0.32 * glow)), 5.5);
  ctx.stroke(ribbons, ink(tint.alpha(0.57 * glow)), 3.2);
  ctx.stroke(light, ink(bright.alpha(0.92 * glow)), 1.35);
}

function coils(f, ctx, tx, ty, tint) {
  const t = f.t;
  const q = phase(t, 0.27, 0.78);
  if (q <= 0 || q >= 1) return;
  const fade = Math.sin(Math.PI * q);
  const radii = Math.min(164, f.pad.width * 0.33) * (1 - easeInOut(q));
  const stretch = f.pad.height * (1 - easeInOut(q));
  const paths = [new Path(), new Path()];
  for (let i = 0; i < 6; i++) {
    const span = 0.8 + closeHash(i, 85, f.seed) * 1.1;
    for (let j = 0; j <= 12; j++) {
      const u = j / 12;
      const a = i * 1.94 + q * 8 + u * span;
      const x = tx + Math.sin(a) * radii * (0.55 + 0.09 * i);
      const y = ty + stretch * (f.floating ? ((i - 2.5) * 0.15) : (0.11 + i * 0.087))
        + stretch * (Math.cos(a) * 0.065 - u * 0.13);
      if (j === 0) paths[i % 2].move(point(x, y)); else paths[i % 2].addLine(point(x, y));
    }
  }
  ctx.stroke(paths[0], ink(tint.alpha(fade * 0.35)), 4.6);
  ctx.stroke(paths[1], ink(tint.alpha(fade * 0.44)), 2.6);
  ctx.stroke(paths[0], ink(ice.alpha(fade * 0.64)), 1.1);
}

function glitter(f, ctx, tx, ty, tint, bright) {
  const t = f.t, r = f.pad;
  if (t < 0.055 || t >= 0.93) return;
  const m = f.cells;
  const glints = new Path(), glows = new Path(), tails = new Path();
  for (let i = 0; i < 310; i++) {
    const rx = closeHash(i, 1, f.seed), ry = closeHash(i, 2, f.seed);
    const c = m.color(Math.floor(rx * m.cols), Math.floor(ry * m.rows));
    if (c.a < 0.17) continue;
    const q = closeHash(i, 3, f.seed), d = closeHash(i, 4, f.seed);
    const start = 0.056 + 0.29 * (1 - ry) + q * 0.102;
    const end = 0.61 + 0.31 * d;
    if (t <= start || t >= end) continue;
    const v = phase(t, start, end);
    const pull = smoothstep(0.16, 0.95, v);
    const turn = (v * (0.83 + d * 0.46) + q) * Math.PI * 2;
    const swell = Math.sin(Math.PI * v);
    const cx = r.minX + r.width * rx;
    const cy = r.minY + r.height * ry;
    const x = lerp(cx, tx + (q - 0.5) * 6, pull) + Math.sin(turn) * (13 + 51 * q) * swell;
    const y = lerp(cy, ty + d * 3, easeInOut(v)) - (12 + 31 * q) * swell;
    const silver = 0.33 + 0.67 * Math.pow(0.5 + 0.5 * Math.sin(turn * 3 + i * 4), 3);
    const a = smoothstep(0, 0.105, v) * (1 - smoothstep(0.77, 1, v)) * silver;
    const size = (0.50 + 1.56 * d) * (1 - 0.58 * pull);
    const colour = c.mix(i % 9 === 0 ? cream : bright, 0.62 + 0.34 * d);
    ctx.fill(Path.ellipse(rect(x - size, y - size * 1.33, size * 2, size * 2.66)), ink(colour.alpha(a)));
    if (i % 5 === 0 && a > 0.21) {
      const tail = 4 + 14 * swell * q;
      line(tails, x, y + 1, x - Math.cos(turn) * tail * 0.38, y + tail);
    }
    if (i % 17 === 0 && a > 0.45) {
      const s = 1.5 + 3.1 * silver;
      glows.addEllipse(rect(x - s, y - s, s * 2, s * 2));
      line(glints, x - s * 0.61, y, x + s * 0.61, y);
      line(glints, x, y - s, x, y + s);
    }
  }
  const envelope = smoothstep(0.08, 0.24, t) * (1 - smoothstep(0.73, 0.93, t));
  ctx.stroke(tails, ink(navy.alpha(0.43 * envelope)), 2.4);
  ctx.stroke(tails, ink(tint.alpha(0.63 * envelope)), 1.1);
  const add = ctx.copy();
  add.blendMode = 'plusLighter';
  add.fill(glows, ink(tint.alpha(0.24 * envelope)));
  add.stroke(glints, ink(cream.alpha(0.87 * envelope)), 0.9);
}
