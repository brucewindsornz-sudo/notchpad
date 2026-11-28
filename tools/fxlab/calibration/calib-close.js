// Calibration drawing, closing side (Swift twin: Sources/CloseTV.swift on branch fx-lab only).
// Rendered with 4 frames (t = 0, 1/3, 2/3, 1): panel A at t = 0, B at 1/3, C at 2/3 (nothing is drawn at t = 1).
// Compare: node render.js calibration/calib-close.js --frames 4 --compare <mac dir>/tv
export const kind = 'close';
export const duration = 0.8;

const R = (x, y, w, h) => new CGRect(x, y, w, h);
const P = (x, y) => new CGPoint(x, y);
const solid = (r, g, b, a = 1) => Shading.color(new RGBA(r, g, b, a));

export function draw(f, ctx) {
  if (f.t < 0.2) panelA(f, ctx);
  else if (f.t < 0.5) panelB(f, ctx);
  else panelC(f, ctx);
}

// A: gradients and blend modes (pad at 160…660 × 0…290).
function panelA(f, ctx) {
  f.drawPad(ctx, f.pad, 1);
  const modes = ['plusLighter', 'screen', 'multiply', 'destinationOut'];
  for (let i = 0; i < 4; i++) {
    const g = ctx.copy();
    g.blendMode = modes[i];
    g.fill(Path.rect(R(190 + i * 110, 120, 70, 70)), solid(0.2, 0.6, 0.9, 0.8));   // over the pad
    g.fill(Path.rect(R(190 + i * 110, 330, 70, 70)), solid(0.2, 0.6, 0.9, 0.8));   // over empty canvas
  }
  // Conic: five uneven stops, starting at 30°.
  const conic = Gradient.stops([[new RGBA(1, 0, 0), 0], [new RGBA(0, 1, 0), 0.25], [new RGBA(0, 0, 1), 0.5],
    [new RGBA(1, 1, 1), 0.75], [new RGBA(0, 0, 0), 1]]);
  ctx.fill(Path.ellipse(R(20, 20, 120, 120)), Shading.conicGradient(conic, P(80, 80), Angle.degrees(30)));
  // Linear with stops inside 0…1 and end points inside the rect: shows the extension past the ends.
  const lin = Gradient.stops([[new RGBA(1, 0, 0), 0.2], [new RGBA(0, 0, 1), 0.8]]);
  ctx.fill(Path.rect(R(10, 160, 140, 40)), Shading.linearGradient(lin, P(40, 180), P(120, 180)));
  // Radial with a start radius: what is inside the start radius?
  const rad = Gradient.stops([[new RGBA(1, 1, 0), 0], [new RGBA(1, 0, 0), 0.5], [new RGBA(1, 0, 0, 0), 1]]);
  ctx.fill(Path.rect(R(20, 220, 120, 120)), Shading.radialGradient(rad, P(80, 280), 15, 55));
  // Hard edge (two stops at 0.5), and stops given out of order.
  const hard = Gradient.stops([[new RGBA(0, 1, 0), 0], [new RGBA(0, 1, 0), 0.5], [new RGBA(0.6, 0, 1), 0.5], [new RGBA(0.6, 0, 1), 1]]);
  ctx.fill(Path.rect(R(680, 20, 120, 40)), Shading.linearGradient(hard, P(680, 0), P(800, 0)));
  const unsorted = Gradient.stops([[new RGBA(1, 0, 0), 0.8], [new RGBA(0, 0, 1), 0.2]]);
  ctx.fill(Path.rect(R(680, 80, 120, 40)), Shading.linearGradient(unsorted, P(680, 0), P(800, 0)));
  // Gradient.colors with three colours, vertical.
  const three = Gradient.colors([new RGBA(1, 1, 1), new RGBA(1, 0.5, 0), new RGBA(0, 0, 0, 0)]);
  ctx.fill(Path.rect(R(680, 140, 120, 120)), Shading.linearGradient(three, P(0, 140), P(0, 260)));
  // A conic in a rotated, scaled context.
  const g2 = ctx.copy();
  g2.translateBy(740, 360);
  g2.rotate(Angle.degrees(45));
  g2.scaleBy(1, 0.5);
  g2.fill(Path.ellipse(R(-50, -50, 100, 100)), Shading.conicGradient(conic, P(0, 0), Angle.degrees(0)));
}

// B: filters, over empty canvas.
function panelB(f, ctx) {
  const white = solid(1, 1, 1);
  const s1 = ctx.copy();
  s1.addFilter(Filter.shadow(new RGBA(1, 0, 0, 1), 8, 12, 10));
  s1.fill(Path.rect(R(30, 30, 60, 60)), white);
  const s2 = ctx.copy();
  s2.addFilter(Filter.shadow(new RGBA(1, 0, 0, 1), 8, 12, 10, { shadowOnly: true }));
  s2.fill(Path.rect(R(140, 30, 60, 60)), white);
  const s3 = ctx.copy();                      // two shadows stacked
  s3.addFilter(Filter.shadow(new RGBA(0, 1, 0, 1), 3, -10, 0));
  s3.addFilter(Filter.shadow(new RGBA(0, 0, 1, 1), 3, 0, 14));
  s3.fill(Path.rect(R(250, 30, 60, 60)), white);
  // Blur: plain, then blur added after scaleBy(3), then blur added before scaleBy(3).
  const b1 = ctx.copy();
  b1.addFilter(Filter.blur(4));
  b1.fill(Path.rect(R(370, 40, 40, 40)), white);
  const b2 = ctx.copy();
  b2.translateBy(450, 30);
  b2.scaleBy(3, 3);
  b2.addFilter(Filter.blur(4));
  b2.fill(Path.rect(R(0, 0, 20, 20)), white);
  const b3 = ctx.copy();
  b3.addFilter(Filter.blur(4));
  b3.translateBy(580, 30);
  b3.scaleBy(3, 3);
  b3.fill(Path.rect(R(0, 0, 20, 20)), white);
  const b4 = ctx.copy();                      // blur on a thin stroke
  b4.addFilter(Filter.blur(2));
  b4.stroke(Path.ellipse(R(700, 30, 80, 80)), white, 2);
  // alphaThreshold: metaballs (0.5…1) and a band (0.2…0.6).
  const m1 = ctx.copy();
  m1.addFilter(Filter.alphaThreshold(0.5, 1, new RGBA(0.2, 0.8, 0.4)));
  m1.drawLayer((l) => {
    l.addFilter(Filter.blur(10));
    for (let i = 0; i < 5; i++) l.fill(Path.ellipse(R(30 + i * 50, 170 + (i % 2) * 30, 50, 50)), white);
  });
  const m2 = ctx.copy();
  m2.addFilter(Filter.alphaThreshold(0.2, 0.6, new RGBA(1, 0.8, 0.2)));
  m2.drawLayer((l) => {
    l.addFilter(Filter.blur(10));
    l.fill(Path.ellipse(R(340, 170, 80, 80)), white);
  });
  // colorMatrix: red/blue swap on orange; identity plus 0.5 red offset on 50% black.
  const c1 = ctx.copy();
  c1.addFilter(Filter.colorMatrix([0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0]));
  c1.fill(Path.rect(R(460, 170, 60, 60)), solid(1, 0.5, 0));
  const c2 = ctx.copy();
  c2.addFilter(Filter.colorMatrix([1, 0, 0, 0, 0.5, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]));
  c2.fill(Path.rect(R(540, 170, 60, 60)), solid(0, 0, 0, 0.5));
  // Colour filters on a rainbow strip, one copy each.
  const rainbow = Gradient.colors([new RGBA(1, 0, 0), new RGBA(1, 1, 0), new RGBA(0, 1, 0), new RGBA(0, 1, 1),
    new RGBA(0, 0, 1), new RGBA(1, 0, 1)]);
  const filters = [null, Filter.brightness(0.3), Filter.contrast(0.5), Filter.saturation(0.3), Filter.hueRotation(Angle.degrees(90)),
    Filter.grayscale(1), Filter.colorInvert(1), Filter.colorMultiply(new RGBA(0.5, 1, 1))];
  for (let i = 0; i < filters.length; i++) {
    const g = ctx.copy();
    if (filters[i]) g.addFilter(filters[i]);
    const y = 270 + i * 22;
    g.fill(Path.rect(R(30, y, 300, 18)), Shading.linearGradient(rainbow, P(30, 0), P(330, 0)));
    g.fill(Path.rect(R(340, y, 60, 18)), solid(0.5, 0.5, 0.5));
  }
  // Opacity with a blur and a shadow (is opacity applied after the filter?).
  const o1 = ctx.copy();
  o1.opacity = 0.5;
  o1.addFilter(Filter.shadow(new RGBA(0, 0, 0, 1), 6, 8, 8));
  o1.fill(Path.rect(R(460, 300, 80, 80)), white);
}

// C: layers and clips.
function panelC(f, ctx) {
  f.drawPad(ctx, f.pad, 1);
  const red = solid(1, 0, 0);
  // L1: opacity 0.5 outside a layer with two overlapping squares.
  const l1 = ctx.copy();
  l1.opacity = 0.5;
  l1.drawLayer((l) => {
    l.fill(Path.rect(R(10, 10, 60, 60)), red);
    l.fill(Path.rect(R(40, 40, 60, 60)), red);
  });
  // L1b: the same without a layer.
  const l1b = ctx.copy();
  l1b.opacity = 0.5;
  l1b.fill(Path.rect(R(10, 110, 60, 60)), red);
  l1b.fill(Path.rect(R(40, 140, 60, 60)), red);
  // L2: transform before the layer.
  const l2 = ctx.copy();
  l2.translateBy(20, 220);
  l2.scaleBy(1.5, 1.5);
  l2.drawLayer((l) => { l.fill(Path.rect(R(0, 0, 40, 40)), solid(0, 1, 0)); });
  // L3: plusLighter outside a layer with two overlapping greys, over the pad.
  const l3 = ctx.copy();
  l3.blendMode = 'plusLighter';
  l3.drawLayer((l) => {
    l.fill(Path.rect(R(190, 20, 80, 80)), solid(0.4, 0.4, 0.4));
    l.fill(Path.rect(R(230, 60, 80, 80)), solid(0.4, 0.4, 0.4));
  });
  // L4: blur outside a layer (applied once or twice?).
  const l4 = ctx.copy();
  l4.addFilter(Filter.blur(3));
  l4.drawLayer((l) => { l.fill(Path.rect(R(350, 30, 60, 60)), solid(1, 1, 1)); });
  // L5: clip outside a layer, and the layer draws past it.
  const l5 = ctx.copy();
  l5.clip(Path.ellipse(R(440, 20, 90, 90)));
  l5.drawLayer((l) => { l.fill(Path.rect(R(420, 0, 130, 130)), solid(1, 0.5, 0)); });
  // L6: destinationOut inside a layer cuts the layer only, not the pad under it.
  ctx.drawLayer((l) => {
    l.fill(Path.rect(R(550, 20, 100, 100)), solid(1, 1, 1));
    l.blendMode = 'destinationOut';
    l.fill(Path.ellipse(R(575, 45, 50, 50)), solid(0, 0, 0));
  });
  // L7: destinationOut straight on ctx cuts the pad.
  const l7 = ctx.copy();
  l7.blendMode = 'destinationOut';
  l7.fill(Path.ellipse(R(575, 160, 50, 50)), solid(0, 0, 0));
  // Clips, below the pad.
  const c1 = ctx.copy();
  c1.clip(Path.ellipse(R(50, 320, 80, 80)), { inverse: true });
  c1.fill(Path.rect(R(20, 300, 140, 120)), solid(0.2, 0.4, 1));
  const c2 = ctx.copy();
  c2.clip(Path.rect(R(200, 300, 120, 120)));
  c2.clip(Path.ellipse(R(230, 330, 60, 60)), { inverse: true });
  c2.fill(Path.rect(R(180, 290, 160, 160)), solid(0.2, 1, 0.6));
  const ring = new Path((p) => { p.addEllipse(R(360, 300, 120, 120)); p.addEllipse(R(390, 330, 60, 60)); });
  const c3 = ctx.copy();
  c3.clip(ring, { eoFill: true });
  c3.fill(Path.rect(R(350, 290, 140, 140)), solid(1, 0.9, 0.2));
  const c4 = ctx.copy();
  c4.clipToLayer((l) => { l.fill(Path.ellipse(R(510, 310, 100, 100)), solid(1, 1, 1)); }, { opacity: 0.5 });
  c4.fill(Path.rect(R(500, 300, 120, 120)), solid(1, 0.3, 0.8));
  const c5 = ctx.copy();
  c5.clip(Path.rect(R(660, 300, 80, 80)));
  c5.translateBy(40, 40);
  c5.fill(Path.rect(R(660, 300, 80, 80)), solid(0.6, 0.6, 1));
  // A clip set inside a layer is the layer's own.
  ctx.drawLayer((l) => {
    l.clip(Path.ellipse(R(680, 20, 120, 120)), { inverse: true });
    l.fill(Path.rect(R(690, 30, 100, 100)), solid(0.5, 1, 1));
  });
}
