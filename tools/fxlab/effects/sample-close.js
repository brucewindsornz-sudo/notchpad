// Port of Sources/CloseStargate.swift (the placeholder sample effect), line for line.
// The pad lifts into the notch while cells of it fly off as sparks.
export const kind = 'close';
export const duration = 0.8;

export function draw(f, ctx) {
  const lift = easeIn(phase(f.t, 0.0, 0.8));                  // stage 1: 0 → 0.8 of the run
  // The pad, squeezed towards the sink.
  const r = new CGRect(lerp(f.pad.minX, f.sink.minX, lift), lerp(f.pad.minY, f.sink.minY, lift),
    lerp(f.pad.width, f.sink.width, lift), lerp(f.pad.height, f.sink.height, lift));
  f.drawPad(ctx, r, 1 - phase(f.t, 0.6, 0.8));
  // A glow line along the bottom edge.
  const glow = Math.sin(Math.PI * phase(f.t, 0.0, 0.8));
  const g = ctx.copy();                                         // Swift: var g = ctx
  g.blendMode = 'plusLighter';
  g.addFilter(Filter.blur(6));
  g.fill(Path.rect(new CGRect(r.minX, r.maxY - 3, r.width, 6)), Shading.color(f.accent.alpha(0.8 * glow)));
  // Sparks: every 5th cell of the pad picture flies off, in its own colour.
  const rng = new CloseRNG(f.seed);
  let row = 0;
  while (row < f.cells.rows) {
    let col = 0;
    while (col < f.cells.cols) {
      const angle = rng.range(0, Math.PI * 2);
      const speed = rng.range(40, 160);
      const start = rng.range(0, 0.4);
      const c = f.cells.color(col, row);
      col += 5;
      if (c.a <= 0) continue;
      const life = phase(f.t, start, start + 0.5);
      if (life <= 0 || life >= 1) continue;
      const cell = f.cells.rect(col - 5, row);
      const x = cell.midX + Math.cos(angle) * speed * easeOut(life);
      const y = cell.midY + Math.sin(angle) * speed * easeOut(life) + 60 * life * life;
      ctx.fill(Path.rect(new CGRect(x - 1.5, y - 1.5, 3, 3)),
        Shading.color(c.mix(f.accent, life).alpha(1 - life)));
    }
    row += 5;
  }
}
