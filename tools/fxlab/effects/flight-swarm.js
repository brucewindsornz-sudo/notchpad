export const kind = 'flight';
export const duration = 1.31;

// 0-.18: a lifting shingle peels away, followed by its neighbours.
// .13-.35: the scattered pieces narrow into a split flock. .30-.73:
// two banks ripple through the flock. .64-.94: approaching pieces fan
// out, pitch flat and knit into the docked picture. .92-1: the last seam settles.
function swarmTile(r, col, row, cols, rows, seed) {
  function point(i, j) {
    const h = closeHash(i, j, seed);
    const k = closeHash(i, j, seed ^ 0xF103);
    const dx = i === 0 || i === cols ? 0 : .60 * (h - .5);
    const dy = j === 0 || j === rows ? 0 : .44 * (k - .5);
    return new CGPoint(r.minX + r.width * (i + dx) / cols, r.minY + r.height * (j + dy) / rows);
  }
  return new Path(p => {
    p.addLines([point(col, row), point(col + 1, row), point(col + 1, row + 1), point(col, row + 1)]);
    p.closeSubpath();
  });
}

function swarmWing(x, y, angle, len, w) {
  const ux = Math.cos(angle), uy = Math.sin(angle);
  function pt(a, b) { return new CGPoint(x + ux * a - uy * b, y + uy * a + ux * b); }
  return [pt(len, 0), pt(-.60 * len, w), pt(-.25 * len, 0), pt(-.94 * len, -.72 * w)];
}

function swarmClip(ctx, path) {
  const g = ctx.copy();
  g.clip(path);
  return g;
}

export function draw(f, ctx) {
  const t = f.t;
  if (t <= 0) { f.drawFrom(ctx); return; }
  if (t >= 1) { f.drawTo(ctx); return; }
  const dx = f.to.midX - f.from.midX, dy = f.to.midY - f.from.midY;
  const d = Math.max(1, f.distance), ux = dx / d, uy = dy / d, hx = -uy, hy = ux;
  const room = Math.max(5, Math.min(115, f.size.width - Math.max(f.from.midX, f.to.midX) - 42));
  const bow = Math.min(room, 34 + d * .17);
  const cols = Math.max(8, Math.min(14, Math.round(f.from.width / 38)));
  const rows = Math.max(5, Math.min(9, Math.round(f.from.height / 37)));
  const keep = new Path(), landed = new Path(), glints = new Path(), trails = new Path();
  const pewter = f.dark ? new RGBA(.54, .65, .75) : new RGBA(.22, .27, .36);
  const edge = f.accent.mix(pewter, .48);
  const spec = edge.mix(RGBA.white, .55);
  const fromBase = swarmClip(ctx, f.fromPath), toBase = swarmClip(ctx, f.toPath);

  for (let row = 0; row < rows; row++) for (let col = 0; col < cols; col++) {
    const u = (col + .5) / cols, v = (row + .5) / rows;
    const n = closeHash(col, row, f.seed ^ 0xC729), m = closeHash(col, row, f.seed ^ 0x26A6);
    const lx = (u - .5), ly = (v - .5);
    const front = clamp01(.5 + .85 * (ux * lx + uy * ly));
    const launch = .020 + .197 * (1 - front) + .042 * n;
    const landing = .735 + .172 * (1 - front) + .026 * m;
    const aTile = () => swarmTile(f.from, col, row, cols, rows, f.seed);
    const bTile = () => swarmTile(f.to, col, row, cols, rows, f.seed);
    if (t <= launch) { keep.addPath(aTile()); continue; }
    if (t >= landing) {
      landed.addPath(bTile());
      if (t - landing < .07 && n > .47) {
        const x = f.to.minX + f.to.width * col / cols, y = f.to.minY + f.to.height * v;
        const shine = Math.sin(Math.PI * phase(t, landing, landing + .07));
        glints.move(new CGPoint(x, y + 8 * shine));
        glints.addLine(new CGPoint(x + 2, y - 7 * shine));
      }
      continue;
    }

    const q = phase(t, launch, landing);
    const p = smoothstep(0, 1, q);
    const gather = smoothstep(.02, .28, q) * (1 - smoothstep(.69, 1, q));
    const roll = Math.sin(p * Math.PI * 2.4 - .9);
    const bank = Math.sin(p * 12 - v * 5 + u * 2);
    const lift = Math.sin(Math.PI * p);
    const cx = lerp(f.from.midX, f.to.midX, p) + hx * bow * lift;
    const cy = lerp(f.from.midY, f.to.midY, p) + hy * bow * lift;
    const ax = lerp(f.from.width, f.to.width, p) * lx;
    const ay = lerp(f.from.height, f.to.height, p) * ly;
    const along = (ax * ux + ay * uy) * .6 + (m - .5) * 60 + 21 * bank;
    const spread = 1 + .35 * roll;
    const across = spread * ((ax * hx + ay * hy) * .37 + (n - .5) * 47);
    const fork = (n > .50 ? 1 : -1) * (23 + 14 * roll) * Math.sin(2.4 * p + .4);
    const x = cx + lerp(ax, ux * along + hx * (across + fork), gather);
    const y = cy + lerp(ay, uy * along + hy * (across + fork), gather);

    if (q < .23 || q > .78) {
      const out = q < .23;
      const fold = out ? smoothstep(0, .23, q) : 1 - smoothstep(.78, 1, q);
      const rect = out ? f.from : f.to, tile = out ? aTile() : bTile();
      const g = ctx.copy();
      g.translateBy(x, y);
      g.rotate((n - .5) * 2.1 * fold);
      g.scaleBy(1 - .61 * fold, 1 - .80 * fold);
      g.translateBy(-(rect.minX + rect.width * u), -(rect.minY + rect.height * v));
      g.clip(tile);
      g.clip(out ? f.fromPath : f.toPath);
      const alpha = 1 - smoothstep(.56, 1, fold);
      if (out) f.drawFrom(g, null, alpha);
      else f.drawTo(g, null, alpha);
    }

    const on = smoothstep(.10, .26, q) * (1 - smoothstep(.77, .91, q));
    if (on > 0) {
      const from = f.fromCells.color(Math.floor(u * f.fromCells.cols), Math.floor(v * f.fromCells.rows));
      const to = f.toCells.color(Math.floor(u * f.toCells.cols), Math.floor(v * f.toCells.rows));
      const cell = from.mix(to, p), metal = cell.mix(edge, .33 + .38 * m);
      const heading = Math.atan2(dy + hy * bow * Math.PI * Math.cos(Math.PI * p),
        dx + hx * bow * Math.PI * Math.cos(Math.PI * p));
      const angle = heading + .54 * bank + .48 * roll + .30 * (n - .5);
      const span = 5.1 + 8.5 * m * m;
      const wing = .87 + 4.8 * (.50 + .50 * Math.cos(p * 19 - v * 6 + n));
      const points = swarmWing(x, y, angle, span, wing);
      const body = new Path(path => { path.addLines(points); path.closeSubpath(); });
      ctx.fill(body, Shading.color(metal.mix(RGBA.black, f.dark ? .15 : .23).alpha(.93 * on)));
      const fold = new Path(path => { path.addLines(points.slice(0, 3)); path.closeSubpath(); });
      ctx.fill(fold, Shading.color(metal.mix(spec, .36 + .51 * (.5 + .5 * bank)).alpha(.96 * on)));
      if (n > .71 && on > .5) {
        trails.move(new CGPoint(x - Math.cos(angle) * (span + 8 + 16 * m),
          y - Math.sin(angle) * (span + 8 + 16 * m)));
        trails.addLine(points[2]);
      }
    }
  }
  if (!keep.isEmpty) f.drawFrom(swarmClip(fromBase, keep));
  if (!landed.isEmpty) f.drawTo(swarmClip(toBase, landed));
  ctx.stroke(trails, Shading.color(edge.alpha(.30)), .9);
  toBase.stroke(glints, Shading.color(spec.alpha(.24 * (1 - smoothstep(.92, .99, t)))), 1);
}
