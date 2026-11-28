// Calibration drawing, flight side (Swift twin: Sources/FlightComet.swift on branch fx-lab only).
// Rendered with 4 frames (t = 0, 1/3, 2/3, 1): panel D at t = 1/3, E at 2/3 (t = 0 and 1 show the pads).
// Compare: node render.js calibration/calib-flight.js --frames 4 --compare <mac dir>/flight-comet
export const kind = 'flight';
export const duration = 0.9;

const R = (x, y, w, h) => new CGRect(x, y, w, h);
const P = (x, y) => new CGPoint(x, y);
const solid = (r, g, b, a = 1) => Shading.color(new RGBA(r, g, b, a));

function cross(ctx, p) {
  const c = new Path((q) => { q.move(P(p.x - 6, p.y)); q.addLine(P(p.x + 6, p.y)); q.move(P(p.x, p.y - 6)); q.addLine(P(p.x, p.y + 6)); });
  ctx.stroke(c, solid(1, 0.2, 0.2), 1);
}

export function draw(f, ctx) {
  if (f.t < 0.5) panelD(f, ctx);
  else panelE(f, ctx);
}

// D: strokes and arcs.
function panelD(f, ctx) {
  const white = solid(1, 1, 1);
  const caps = ['butt', 'round', 'square'];
  for (let i = 0; i < 3; i++) {
    const y = 80 + i * 30;
    ctx.stroke(new Path((p) => { p.move(P(60, y)); p.addLine(P(260, y)); }), white, { lineWidth: 12, lineCap: caps[i] });
  }
  ctx.stroke(new Path((p) => { p.move(P(60, 60)); p.addLine(P(60, 160)); p.move(P(260, 60)); p.addLine(P(260, 160)); }), solid(1, 0.2, 0.2), 1);
  const joins = ['miter', 'round', 'bevel'];
  for (let i = 0; i < 3; i++) {
    const x = 320 + i * 150;
    const z = new Path((p) => { p.move(P(x, 170)); p.addLine(P(x + 40, 70)); p.addLine(P(x + 80, 170)); p.addLine(P(x + 100, 80)); });
    ctx.stroke(z, white, { lineWidth: 12, lineJoin: joins[i] });
  }
  const sharp = new Path((p) => { p.move(P(800, 170)); p.addLine(P(830, 70)); p.addLine(P(860, 170)); });
  ctx.stroke(sharp, white, { lineWidth: 10, lineJoin: 'miter', miterLimit: 2 });
  ctx.stroke(sharp.offsetBy(100, 0), white, { lineWidth: 10, lineJoin: 'miter', miterLimit: 10 });
  // Dashes: phase 0, phase 5, round-capped dots, on a rect, an ellipse and a rounded rect.
  const line = (y) => new Path((p) => { p.move(P(60, y)); p.addLine(P(460, y)); });
  ctx.stroke(line(220), white, { lineWidth: 6, dash: [20, 10] });
  ctx.stroke(line(240), white, { lineWidth: 6, dash: [20, 10], dashPhase: 5 });
  ctx.stroke(line(260), white, { lineWidth: 8, lineCap: 'round', dash: [0, 16] });
  ctx.stroke(line(280), white, { lineWidth: 4, lineCap: 'square', dash: [10, 10, 2, 10] });
  ctx.stroke(Path.rect(R(520, 210, 120, 80)), white, { lineWidth: 4, dash: [30, 10] });
  ctx.stroke(Path.ellipse(R(680, 210, 120, 80)), white, { lineWidth: 4, dash: [30, 10] });
  ctx.stroke(Path.roundedRect(R(840, 210, 120, 80), 20), white, { lineWidth: 4, dash: [30, 10] });
  // Arcs: from the centre, 0° → 90°, clockwise false then true; then -45° → 200° both ways.
  const arcs = [[0, 90, false], [0, 90, true], [-45, 200, false], [-45, 200, true]];
  for (let i = 0; i < arcs.length; i++) {
    const c = P(110 + i * 160, 420);
    const wedge = new Path((p) => {
      p.move(c);
      p.addArc(c, 60, Angle.degrees(arcs[i][0]), Angle.degrees(arcs[i][1]), arcs[i][2]);
      p.closeSubpath();
    });
    ctx.fill(wedge, solid(0.3, 0.7, 1, 0.8));
    cross(ctx, P(c.x + 60, c.y));       // where 0° is
  }
  // An arc with no move first, stroked; then one after a line.
  ctx.stroke(new Path((p) => { p.addArc(P(760, 420), 50, Angle.degrees(180), Angle.degrees(0), false); }), white, 6);
  ctx.stroke(new Path((p) => { p.move(P(840, 360)); p.addArc(P(950, 420), 50, Angle.degrees(180), Angle.degrees(270), false); }), white, 6);
  // trimmedPath on a circle: which part is 0.1…0.4?
  ctx.stroke(Path.ellipse(R(1040, 370, 100, 100)), solid(1, 1, 1, 0.25), 6);
  ctx.stroke(Path.ellipse(R(1040, 370, 100, 100)).trimmedPath(0.1, 0.4), solid(1, 0.6, 0.1), 6);
  // Rotation direction: a bar rotated by +30°.
  const g = ctx.copy();
  g.translateBy(110, 600);
  g.rotate(Angle.degrees(30));
  g.fill(Path.rect(R(0, -5, 120, 10)), white);
  ctx.stroke(new Path((p) => { p.move(P(110, 600)); p.addLine(P(260, 600)); }), solid(1, 0.2, 0.2), 1);
  // A stroke in a scaled context: is the line width scaled too?
  const s = ctx.copy();
  s.translateBy(320, 560);
  s.scaleBy(3, 1);
  s.stroke(Path.ellipse(R(0, 0, 40, 80)), white, 4);
  // Quad and cubic curves.
  ctx.stroke(new Path((p) => { p.move(P(520, 640)); p.addQuadCurve(P(680, 640), P(600, 540)); }), white, 4);
  ctx.stroke(new Path((p) => { p.move(P(720, 640)); p.addCurve(P(920, 640), P(760, 520), P(880, 720)); }), white, 4);
}

// E: text.
function panelE(f, ctx) {
  const sizes = [9, 13, 20, 32, 56];
  let y = 90;
  for (const s of sizes) {
    const t = ctx.resolveText('Hxg 0123', { size: s, color: RGBA.white });
    ctx.drawText(t, P(60, y), 'leading');
    cross(ctx, P(60, y));
    y += s * 1.4 + 14;
  }
  const anchors = ['topLeading', 'top', 'topTrailing', 'leading', 'center', 'trailing', 'bottomLeading', 'bottom', 'bottomTrailing'];
  for (let i = 0; i < 9; i++) {
    const p = P(520 + (i % 3) * 200, 120 + Math.floor(i / 3) * 90);
    const t = ctx.resolveText('Ag', { size: 28, color: RGBA.white });
    ctx.drawText(t, p, anchors[i]);
    cross(ctx, p);
  }
  const styles = [['bold', 'default'], ['black', 'default'], ['light', 'default'], ['regular', 'monospaced'],
    ['regular', 'rounded'], ['regular', 'serif'], ['bold', 'monospaced']];
  for (let i = 0; i < styles.length; i++) {
    const t = ctx.resolveText('Things 0O1l', { size: 22, weight: styles[i][0], design: styles[i][1], color: RGBA.white });
    ctx.drawText(t, P(60, 420 + i * 40), 'leading');
  }
  const boxed = ctx.resolveText('in rect', { size: 24, color: new RGBA(1, 0.8, 0.3) });
  ctx.stroke(Path.rect(R(520, 420, 200, 60)), solid(1, 0.2, 0.2), 1);
  ctx.drawTextIn(boxed, R(520, 420, 200, 60));
  // Text with opacity, in a rotated context, and a Japanese glyph.
  const g = ctx.copy();
  g.opacity = 0.5;
  g.translateBy(820, 520);
  g.rotate(Angle.degrees(-20));
  g.drawText(ctx.resolveText('Tilted', { size: 30, weight: 'bold', color: RGBA.white }), P(0, 0), 'center');
  cross(ctx, P(820, 520));
  ctx.drawText(ctx.resolveText('ﾊﾟ日本', { size: 30, design: 'monospaced', color: new RGBA(0.4, 1, 0.5) }), P(820, 640), 'center');
  cross(ctx, P(820, 640));
}
