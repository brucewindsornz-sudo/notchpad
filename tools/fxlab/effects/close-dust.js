export const kind = 'close';
export const duration = 1.04;

// 0-.14: the lower-right edge flakes. .10-.65: a torn front climbs across
// the note. .16-.82: flakes turn to dust in the wind. .70-1: the last eddy
// curls into the notch (or the middle of the loose card).
function dustRag(v, f) {
  return 53 * (closeNoise(1.5, v * 5.2, f.seed) - .5)
    + 23 * (closeNoise(2.9, v * 16, f.seed ^ 0xDA57) - .5)
    + 14 * (closeNoise(4.7, v * 53, f.seed ^ 0x9BA7) - .5);
}

function dustFront(v, f, sweep) {
  return f.pad.maxX + 24 + .31 * f.pad.width * (1 - v)
    + dustRag(v, f) - sweep * (1.31 * f.pad.width + 68);
}

function dustGrain(x, y, r, angle, aspect) {
  const u = Math.cos(angle) * r, v = Math.sin(angle) * r;
  const sx = -v * aspect, sy = u * aspect;
  return new Path(p => {
    p.addLines([new CGPoint(x - u, y - v), new CGPoint(x + sx, y + sy),
      new CGPoint(x + u, y + v), new CGPoint(x + .6 * u - sx, y + .6 * v - sy)]);
    p.closeSubpath();
  });
}

export function draw(f, ctx) {
  const t = f.t;
  if (t <= 0) { f.drawPad(ctx); return; }
  if (t >= 1) return;
  const {pad, cells} = f;
  const mist = f.dark ? new RGBA(.70, .73, .76) : new RGBA(.28, .26, .23);
  const rim = f.accent.mix(mist, .66);
  const sweep = smoothstep(.004, .74, t);
  if (t < .74) {
    const hull = new Path(), crust = new Path(), filigree = new Path();
    const count = Math.max(16, Math.ceil(pad.height / 3.5));
    hull.move(new CGPoint(pad.minX - 4, pad.minY - 1));
    for (let i = 0; i <= count; i++) {
      const v = i / count, y = pad.minY + pad.height * v;
      const x = dustFront(v, f, sweep);
      hull.addLine(new CGPoint(x, y));
      if (i === count || x < pad.minX - 8 || x > pad.maxX + 8) continue;
      const y2 = y + pad.height / count, x2 = dustFront((i + 1) / count, f, sweep);
      const n = closeHash(i, 6, f.seed), bite = 1 + 10 * n * n;
      crust.move(new CGPoint(x - bite, y));
      crust.addLine(new CGPoint(x, y));
      crust.addLine(new CGPoint(x2, y2));
      crust.addLine(new CGPoint(x2 - bite * .6, y2));
      crust.closeSubpath();
      if (n > .59) {
        filigree.move(new CGPoint(x - .7, y));
        filigree.addLine(new CGPoint(lerp(x, x2, .68) - .7, lerp(y, y2, .68)));
      }
    }
    hull.addLine(new CGPoint(pad.minX - 4, pad.maxY + 1));
    hull.closeSubpath();
    const intact = ctx.copy();
    intact.clip(hull);
    f.drawPad(intact);
    const edge = ctx.copy();
    edge.clip(f.padPath);
    const strike = smoothstep(.02, .15, t);
    edge.fill(crust, Shading.color(mist.alpha(.25 * strike)));
    edge.stroke(filigree, Shading.color(rim.alpha(.69 * strike)), 1.15);
  }

  // Several small, overlapping clouds keep the gust visible without blurring
  // the backdrop or drawing a uniform veil over the collapsing pad.
  for (let i = 0; i < 16 && t < .88; i++) {
    const n = closeHash(i, 0, f.seed), m = closeHash(i, 5, f.seed);
    const v = (i + .25 + .5 * n) / 16;
    const lag = .085 + .14 * n;
    const x0 = dustFront(v, f, smoothstep(.004, .74, t - lag));
    const pe = smoothstep(pad.minX - 25, pad.minX + 18, x0) *
      (1 - smoothstep(pad.maxX - 39, pad.maxX - 2, x0));
    if (pe <= 0) continue;
    const drift = 30 + 68 * n;
    const cx = x0 + drift, cy = pad.minY + v * pad.height - 30 * (m - .28);
    const radius = 26 + m * 42;
    const g = ctx.copy();
    g.translateBy(cx, cy);
    g.rotate(-.27 + m * .44);
    g.scaleBy(1, .38 + .36 * m);
    const fog = mist.mix(f.bg, .29).alpha(pe * (.10 + .07 * m));
    const gradient = Gradient.colors([fog, fog.alpha(fog.a * .47), fog.alpha(0)]);
    g.fill(Path.ellipse(new CGRect(-radius, -radius, 2 * radius, 2 * radius)),
      Shading.radialGradient(gradient, CGPoint.zero, 0, radius));
  }

  // A stratified sample catches ink as well as paper. The air turns over in
  // broad folds; the per-grain variation is in drag, spin and lifetime.
  const sample = Math.min(1, 1520 / (cells.rows * cells.cols));
  const wind = new Path();
  for (let row = 0; row < cells.rows; row++) {
    for (let col = 0; col < cells.cols; col++) {
      if (closeHash(col, row, f.seed ^ 0xCAB1) > sample) continue;
      const c = cells.color(col, row);
      if (c.a < .09) continue;
      const cell = cells.rect(col, row);
      const n = closeHash(col, row, f.seed ^ 0x3119);
      const m = closeHash(col, row, f.seed ^ 0xAB3D);
      const j = closeHash(col, row, f.seed ^ 0x51ED);
      const px = cell.minX + n * cells.size;
      const py = cell.minY + m * cells.size;
      const v = (py - pad.minY) / pad.height;
      const gap = px - dustFront(v, f, sweep) + 5 * j;
      if (gap <= 0) continue;
      const at = clamp01((dustFront(v, f, 0) - px - 5 * j) / (1.31 * pad.width + 68));
      // Invert the smoothstep sweep to give each flake its own release time.
      const born = .004 + .736 * (.5 - Math.sin(Math.asin(1 - 2 * at) / 3));
      const life = phase(t, born, Math.min(.98, born + .24 + .29 * n));
      if (life <= 0 || life >= 1) continue;
      const age = Math.pow(life, 1.18);
      const gust = Math.sin(v * 17 + age * 6 + px * .014);
      const drift = (37 + 164 * m) * age;
      const x0 = px + drift + 21 * gust * age;
      const y0 = py + (-94 + 148 * j) * age + 30 * Math.sin(v * 13 - age * 7) * age;
      const gather = smoothstep(.65, .94, t) * smoothstep(.43, .61, born);
      const x = lerp(x0, f.target.x, gather);
      const y = lerp(y0, f.target.y + 1, gather);
      const flake = n > .87 ? 2.6 + 2.1 * j : .66 + 1.9 * m * m;
      const size = flake * (1 - .62 * age);
      const a = c.a * smoothstep(0, .065, life) * (1 - smoothstep(.42, 1, life));
      const ash = c.mix(mist, (.32 + .44 * m) * (.88 + .12 * life));
      const angle = .3 + 5.8 * n + (5 * j - 2.5) * age;
      ctx.fill(dustGrain(x, y, size, angle, .28 + .63 * j), Shading.color(ash.alpha(a)));
      if (j > .69 && life > .12 && life < .8) {
        const wx = x - 3.5 - 12 * m, wy = y + 4 * gust;
        wind.move(new CGPoint(wx, wy));
        wind.addQuadCurve(new CGPoint(x - .8, y), new CGPoint(lerp(wx, x, .54), wy + 1.8));
      }
    }
  }
  ctx.stroke(wind, Shading.color(mist.alpha(.14 * (1 - smoothstep(.76, .96, t)))), .65);

  const settle = smoothstep(.79, .91, t) * (1 - smoothstep(.91, .985, t));
  if (settle > 0) {
    const pt = f.target, r = 9 - 5 * phase(t, .79, .985);
    const g = Gradient.colors([rim.alpha(.26 * settle), rim.alpha(0)]);
    ctx.fill(Path.ellipse(new CGRect(pt.x - r, pt.y - r, 2 * r, 2 * r)),
      Shading.radialGradient(g, pt, 0, r));
  }
}
