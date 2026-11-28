// fxlab: a JavaScript mirror of NotchPad's Swift animation API (Sources/CloseEffects.swift, FlightEffects.swift
// and SwiftUI's GraphicsContext). The same code, the same helper names and the same numbers must give the
// same picture on both sides, so every helper here copies the Swift one line for line. See PORTING.md.
//
// Everything is exported, and also installed on globalThis by the harness page, so effect files can use
// the names directly, just as Swift files in one module do.

// MARK: - Helpers (CloseEffects.swift)

export function clamp01(x) { return x < 0 ? 0 : (x > 1 ? 1 : x); }
export function lerp(a, b, t) { return a + (b - a) * t; }
export function phase(t, a, b) { return clamp01((t - a) / (b - a)); }
export function easeIn(t) { return t * t * t; }
export function easeOut(t) { const u = 1 - t; return 1 - u * u * u; }
export function easeInOut(t) { return t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2; }
export function smoothstep(a, b, x) {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
}

// UInt32(truncatingIfNeeded: i) for any JS integer (Swift Int is 64-bit; JS numbers are exact up to 2^53).
function u32(i) {
  i = Math.trunc(i);
  if (i >= -2147483648 && i <= 4294967295) return i >>> 0;
  return Number(BigInt.asUintN(32, BigInt(i)));
}

/** Stateless random number in [0, 1) for a pair of integers. Bit-identical to Swift's closeHash. */
export function closeHash(i, j, seed) {
  let h = Math.imul(u32(i), 374761393) >>> 0;
  h = (h + Math.imul(u32(j), 668265263)) >>> 0;
  h = (h + Math.imul(seed >>> 0, 2246822519 | 0)) >>> 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0;
  h = (h ^ (h >>> 16)) >>> 0;
  return h / 4294967296.0;
}

/** Seeded random sequence (mulberry32). `new CloseRNG(seed)` = Swift `var rng = CloseRNG(seed)`. */
export class CloseRNG {
  constructor(seed) { this.s = seed >>> 0; }
  next() {
    this.s = (this.s + 0x6D2B79F5) >>> 0;
    let t = this.s;
    t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0;
    t = (t ^ ((t + Math.imul(t ^ (t >>> 7), t | 61)) >>> 0)) >>> 0;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296.0;
  }
  range(a, b) { return a + (b - a) * this.next(); }
  /** 0 ..< n */
  int(n) { return Math.floor(this.next() * n); }
  /** Swift structs copy on assignment: `var r2 = rng` is `const r2 = rng.copy()` here. */
  copy() { const r = new CloseRNG(0); r.s = this.s; return r; }
}

/** Smooth 2-D value noise in [0, 1). */
export function closeNoise(x, y, seed) {
  const xf = Math.floor(x), yf = Math.floor(y);
  const xi = xf, yi = yf;
  const fx = x - xf, fy = y - yf;
  const u = fx * fx * (3 - 2 * fx), v = fy * fy * (3 - 2 * fy);
  const a = closeHash(xi, yi, seed), b = closeHash(xi + 1, yi, seed);
  const c = closeHash(xi, yi + 1, seed), d = closeHash(xi + 1, yi + 1, seed);
  return lerp(lerp(a, b, u), lerp(c, d, u), v);
}

// MARK: - Colour

export class RGBA {
  constructor(r, g, b, a = 1) { this.r = r; this.g = g; this.b = b; this.a = a; }
  mix(o, t) { return new RGBA(lerp(this.r, o.r, t), lerp(this.g, o.g, t), lerp(this.b, o.b, t), lerp(this.a, o.a, t)); }
  alpha(a) { return new RGBA(this.r, this.g, this.b, a); }
  /** Swift `c.color` (a SwiftUI Color). Here it is the same object; kept so ported code reads the same. */
  get color() { return this; }
  css() {
    const k = (v) => Math.round(clamp01(v) * 255);
    return `rgba(${k(this.r)},${k(this.g)},${k(this.b)},${clamp01(this.a)})`;
  }
  static hex(s) {
    s = s.replace('#', '');
    if (s.length === 3) s = s.split('').map((c) => c + c).join('');
    const v = parseInt(s, 16);
    return new RGBA(((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255, 1);
  }
}
RGBA.white = new RGBA(1, 1, 1, 1);
RGBA.black = new RGBA(0, 0, 0, 1);
RGBA.clear = new RGBA(0, 0, 0, 0);

// MARK: - Geometry (CoreGraphics)

export class CGPoint {
  constructor(x = 0, y = 0) { this.x = x; this.y = y; }
  static get zero() { return new CGPoint(0, 0); }
  applying(m) { return m.apply(this); }
}
export class CGSize {
  constructor(width = 0, height = 0) { this.width = width; this.height = height; }
  static get zero() { return new CGSize(0, 0); }
}
export class CGRect {
  // CGRect(x:, y:, width:, height:) and CGRect(origin:, size:) both work: new CGRect(x, y, w, h) or new CGRect(p, s).
  constructor(x = 0, y = 0, width = 0, height = 0) {
    if (x instanceof CGPoint) { const o = x, s = y; this.x = o.x; this.y = o.y; this.width = s.width; this.height = s.height; return; }
    this.x = x; this.y = y; this.width = width; this.height = height;
  }
  static get zero() { return new CGRect(0, 0, 0, 0); }
  get origin() { return new CGPoint(this.x, this.y); }
  get size() { return new CGSize(this.width, this.height); }
  // Like CoreGraphics, min/max work on the standardised rectangle (negative sizes are allowed).
  get minX() { return Math.min(this.x, this.x + this.width); }
  get maxX() { return Math.max(this.x, this.x + this.width); }
  get midX() { return this.x + this.width / 2; }
  get minY() { return Math.min(this.y, this.y + this.height); }
  get maxY() { return Math.max(this.y, this.y + this.height); }
  get midY() { return this.y + this.height / 2; }
  get isEmpty() { return this.width === 0 || this.height === 0; }
  get standardized() { return new CGRect(this.minX, this.minY, Math.abs(this.width), Math.abs(this.height)); }
  insetBy(dx, dy) {
    const s = this.standardized;
    const w = s.width - 2 * dx, h = s.height - 2 * dy;
    if (w < 0 || h < 0) return new CGRect(Infinity, Infinity, 0, 0); // CGRect.null
    return new CGRect(s.x + dx, s.y + dy, w, h);
  }
  offsetBy(dx, dy) { return new CGRect(this.x + dx, this.y + dy, this.width, this.height); }
  contains(p) {
    if (p instanceof CGRect) return p.minX >= this.minX && p.maxX <= this.maxX && p.minY >= this.minY && p.maxY <= this.maxY;
    return p.x >= this.minX && p.x < this.maxX && p.y >= this.minY && p.y < this.maxY;
  }
  union(o) {
    const x0 = Math.min(this.minX, o.minX), y0 = Math.min(this.minY, o.minY);
    return new CGRect(x0, y0, Math.max(this.maxX, o.maxX) - x0, Math.max(this.maxY, o.maxY) - y0);
  }
  intersection(o) {
    const x0 = Math.max(this.minX, o.minX), y0 = Math.max(this.minY, o.minY);
    const x1 = Math.min(this.maxX, o.maxX), y1 = Math.min(this.maxY, o.maxY);
    if (x1 < x0 || y1 < y0) return new CGRect(Infinity, Infinity, 0, 0);
    return new CGRect(x0, y0, x1 - x0, y1 - y0);
  }
  intersects(o) { return this.minX < o.maxX && o.minX < this.maxX && this.minY < o.maxY && o.minY < this.maxY; }
}

/** CGAffineTransform(a, b, c, d, tx, ty): x' = a x + c y + tx, y' = b x + d y + ty. */
export class CGAffineTransform {
  constructor(a = 1, b = 0, c = 0, d = 1, tx = 0, ty = 0) { Object.assign(this, { a, b, c, d, tx, ty }); }
  static get identity() { return new CGAffineTransform(); }
  static translation(x, y) { return new CGAffineTransform(1, 0, 0, 1, x, y); }   // CGAffineTransform(translationX:y:)
  static scale(x, y) { return new CGAffineTransform(x, 0, 0, y, 0, 0); }          // CGAffineTransform(scaleX:y:)
  static rotation(a) { const c = Math.cos(a), s = Math.sin(a); return new CGAffineTransform(c, s, -s, c, 0, 0); } // (rotationAngle:)
  /** self then m: Swift `self.concatenating(m)`. */
  concatenating(m) {
    return new CGAffineTransform(
      this.a * m.a + this.b * m.c, this.a * m.b + this.b * m.d,
      this.c * m.a + this.d * m.c, this.c * m.b + this.d * m.d,
      this.tx * m.a + this.ty * m.c + m.tx, this.tx * m.b + this.ty * m.d + m.ty);
  }
  translatedBy(x, y) { return CGAffineTransform.translation(x, y).concatenating(this); }
  scaledBy(x, y) { return CGAffineTransform.scale(x, y).concatenating(this); }
  rotated(a) { return CGAffineTransform.rotation(a).concatenating(this); }
  inverted() {
    const det = this.a * this.d - this.b * this.c;
    if (det === 0) return this;
    const a = this.d / det, b = -this.b / det, c = -this.c / det, d = this.a / det;
    return new CGAffineTransform(a, b, c, d, -(a * this.tx + c * this.ty), -(b * this.tx + d * this.ty));
  }
  apply(p) { return new CGPoint(this.a * p.x + this.c * p.y + this.tx, this.b * p.x + this.d * p.y + this.ty); }
}

/** Angle helpers so ported code can keep Swift's `.degrees(30)` / `.radians(x)` shape: Angle.degrees(30) → radians. */
export const Angle = { radians: (r) => r, degrees: (d) => d * Math.PI / 180 };

// MARK: - Path (SwiftUI.Path)

const K_CIRCLE = 0.5522847498307936; // control-point factor for a quarter circle

/**
 * SwiftUI.Path. Coordinates are points, y downward. A Path is a value in Swift: `var q = p` copies it.
 * Here `p.copy()` does that (methods mutate in place, like Swift's mutating methods).
 */
export class Path {
  constructor(arg) {
    this.ops = [];
    this._p2d = null;
    if (typeof arg === 'function') arg(this);        // Path { p in ... }
    else if (arg instanceof CGRect) this.addRect(arg); // Path(rect)
    else if (arg instanceof Path) this.ops = arg.ops.slice();
  }
  static rect(r) { const p = new Path(); p.addRect(r); return p; }                       // Path(r)
  static ellipse(r) { const p = new Path(); p.addEllipse(r); return p; }                 // Path(ellipseIn: r)
  static roundedRect(r, cornerRadius, style = 'continuous') {                           // Path(roundedRect:cornerRadius:style:)
    const p = new Path(); p.addRoundedRect(r, cornerRadius, style); return p;
  }
  copy() { return new Path(this); }
  _dirty() { this._p2d = null; }
  _last() { for (let i = this.ops.length - 1; i >= 0; i--) { const o = this.ops[i]; if (o.end) return o.end; } return null; }

  move(to) { this.ops.push({ k: 'M', end: to }); this._start = to; this._dirty(); }
  addLine(to) { if (!this._last()) return this.move(to); this.ops.push({ k: 'L', end: to }); this._dirty(); }
  addLines(points) { if (!points.length) return; this.move(points[0]); for (let i = 1; i < points.length; i++) this.addLine(points[i]); }
  addQuadCurve(to, control) { if (!this._last()) this.move(control); this.ops.push({ k: 'Q', c: control, end: to }); this._dirty(); }
  addCurve(to, control1, control2) { if (!this._last()) this.move(control1); this.ops.push({ k: 'C', c1: control1, c2: control2, end: to }); this._dirty(); }
  closeSubpath() { if (this.ops.length) { this.ops.push({ k: 'Z', end: this._start || null }); this._dirty(); } }

  /**
   * SwiftUI `addArc(center:radius:startAngle:endAngle:clockwise:)`, angles in radians.
   * DIRECTION TRAP: SwiftUI's `clockwise: true` in its y-down space turns the way that looks
   * counter-clockwise on screen. Canvas 2D's `counterclockwise: true` also looks counter-clockwise on screen.
   * So Swift `clockwise: x` == canvas `counterclockwise: x`, and this method passes it straight through.
   */
  addArc(center, radius, startAngle, endAngle, clockwise) {
    const sx = center.x + radius * Math.cos(startAngle), sy = center.y + radius * Math.sin(startAngle);
    if (this._last()) this.ops.push({ k: 'L', end: new CGPoint(sx, sy) }); else this.move(new CGPoint(sx, sy));
    this.ops.push({ k: 'A', center, radius, a0: startAngle, a1: endAngle, ccw: !!clockwise,
      end: new CGPoint(center.x + radius * Math.cos(endAngle), center.y + radius * Math.sin(endAngle)) });
    this._dirty();
  }
  addRect(r) {
    this.move(new CGPoint(r.minX, r.minY));
    this.addLine(new CGPoint(r.maxX, r.minY)); this.addLine(new CGPoint(r.maxX, r.maxY)); this.addLine(new CGPoint(r.minX, r.maxY));
    this.closeSubpath();
  }
  addRects(rs) { for (const r of rs) this.addRect(r); }
  /** `addEllipse(in: r)`: starts at the right-hand middle point, like CoreGraphics. */
  addEllipse(r) {
    const cx = r.midX, cy = r.midY, rx = r.width / 2, ry = r.height / 2, kx = rx * K_CIRCLE, ky = ry * K_CIRCLE;
    const P = (x, y) => new CGPoint(x, y);
    this.move(P(cx + rx, cy));
    this.addCurve(P(cx, cy + ry), P(cx + rx, cy + ky), P(cx + kx, cy + ry));
    this.addCurve(P(cx - rx, cy), P(cx - kx, cy + ry), P(cx - rx, cy + ky));
    this.addCurve(P(cx, cy - ry), P(cx - rx, cy - ky), P(cx - kx, cy - ry));
    this.addCurve(P(cx + rx, cy), P(cx + kx, cy - ry), P(cx + rx, cy - ky));
    this.closeSubpath();
  }
  /**
   * Swift `addRoundedRect(in: r, cornerSize: CGSize(width: k, height: k), style: .continuous)`.
   * style 'continuous' (Apple's smooth "squircle" corner, Swift's default) or 'circular'.
   * The continuous corner is the well-known approximation of Apple's curve: close, not pixel-exact.
   */
  addRoundedRect(r, cornerRadius, style = 'continuous') {
    r = r.standardized;
    const P = (x, y) => new CGPoint(x, y);
    const maxR = Math.min(r.width, r.height) / 2;
    let rad = Math.max(0, Math.min(cornerRadius, maxR));
    if (rad <= 0) return this.addRect(r);
    const x0 = r.minX, y0 = r.minY, x1 = r.maxX, y1 = r.maxY;
    if (style === 'continuous' && rad * 1.52866483 <= maxR) {
      const a = 1.52866483 * rad, b = 1.08849296 * rad, c = 0.86840694 * rad, d = 0.63149399 * rad,
        e = 0.07491100 * rad, f = 0.37282383 * rad, g = 0.16905899 * rad;
      this.move(P(x0 + a, y0));
      this.addLine(P(x1 - a, y0));
      this.addCurve(P(x1 - d, y0 + e), P(x1 - b, y0), P(x1 - c, y0));
      this.addCurve(P(x1 - e, y0 + d), P(x1 - f, y0 + g), P(x1 - g, y0 + f));
      this.addCurve(P(x1, y0 + a), P(x1, y0 + c), P(x1, y0 + b));
      this.addLine(P(x1, y1 - a));
      this.addCurve(P(x1 - e, y1 - d), P(x1, y1 - b), P(x1, y1 - c));
      this.addCurve(P(x1 - d, y1 - e), P(x1 - g, y1 - f), P(x1 - f, y1 - g));
      this.addCurve(P(x1 - a, y1), P(x1 - c, y1), P(x1 - b, y1));
      this.addLine(P(x0 + a, y1));
      this.addCurve(P(x0 + d, y1 - e), P(x0 + b, y1), P(x0 + c, y1));
      this.addCurve(P(x0 + e, y1 - d), P(x0 + f, y1 - g), P(x0 + g, y1 - f));
      this.addCurve(P(x0, y1 - a), P(x0, y1 - c), P(x0, y1 - b));
      this.addLine(P(x0, y0 + a));
      this.addCurve(P(x0 + e, y0 + d), P(x0, y0 + b), P(x0, y0 + c));
      this.addCurve(P(x0 + d, y0 + e), P(x0 + g, y0 + f), P(x0 + f, y0 + g));
      this.addCurve(P(x0 + a, y0), P(x0 + c, y0), P(x0 + b, y0));
      this.closeSubpath();
      return;
    }
    const k = rad * K_CIRCLE;
    this.move(P(x0 + rad, y0));
    this.addLine(P(x1 - rad, y0)); this.addCurve(P(x1, y0 + rad), P(x1 - rad + k, y0), P(x1, y0 + rad - k));
    this.addLine(P(x1, y1 - rad)); this.addCurve(P(x1 - rad, y1), P(x1, y1 - rad + k), P(x1 - rad + k, y1));
    this.addLine(P(x0 + rad, y1)); this.addCurve(P(x0, y1 - rad), P(x0 + rad - k, y1), P(x0, y1 - rad + k));
    this.addLine(P(x0, y0 + rad)); this.addCurve(P(x0 + rad, y0), P(x0, y0 + rad - k), P(x0 + rad - k, y0));
    this.closeSubpath();
  }
  /** Swift `addPath(other, transform: m)` (transform optional). */
  addPath(other, transform = null) {
    const src = transform ? other.applying(transform) : other;
    for (const o of src.ops) this.ops.push(o);
    this._dirty();
  }
  /** Swift `path.applying(m)`: a transformed copy. Arcs become curves only if the transform is not a similarity. */
  applying(m) {
    const T = (p) => (p ? m.apply(p) : p);
    const q = new Path();
    const sc = Math.sqrt(Math.abs(m.a * m.d - m.b * m.c));
    const similar = Math.abs(m.a - m.d) < 1e-9 && Math.abs(m.b + m.c) < 1e-9 && m.a * m.d - m.b * m.c > 0;
    for (const o of this.ops) {
      if (o.k === 'A') {
        if (similar) {
          const rot = Math.atan2(m.b, m.a);
          q.ops.push({ ...o, center: T(o.center), radius: o.radius * sc, a0: o.a0 + rot, a1: o.a1 + rot, end: T(o.end) });
        } else {
          for (const c of arcToCurves(o)) q.ops.push({ k: 'C', c1: T(c.c1), c2: T(c.c2), end: T(c.end) });
        }
      } else q.ops.push({ ...o, c: T(o.c), c1: T(o.c1), c2: T(o.c2), end: T(o.end) });
    }
    return q;
  }
  offsetBy(dx, dy) { return this.applying(CGAffineTransform.translation(dx, dy)); }
  get isEmpty() { return this.ops.length === 0; }
  get currentPoint() { return this._last(); }
  /** Swift `path.boundingRect` (tight box of the curves, from sampling). */
  get boundingRect() {
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity, prev = null;
    const add = (p) => { x0 = Math.min(x0, p.x); y0 = Math.min(y0, p.y); x1 = Math.max(x1, p.x); y1 = Math.max(y1, p.y); };
    for (const o of this.ops) {
      if (o.k === 'M' || o.k === 'L') add(o.end);
      else if (o.k === 'Q' || o.k === 'C') {
        for (let i = 1; i <= 16; i++) {
          const t = i / 16, u = 1 - t;
          if (o.k === 'Q') add(new CGPoint(u * u * prev.x + 2 * u * t * o.c.x + t * t * o.end.x, u * u * prev.y + 2 * u * t * o.c.y + t * t * o.end.y));
          else add(new CGPoint(u * u * u * prev.x + 3 * u * u * t * o.c1.x + 3 * u * t * t * o.c2.x + t * t * t * o.end.x,
            u * u * u * prev.y + 3 * u * u * t * o.c1.y + 3 * u * t * t * o.c2.y + t * t * t * o.end.y));
        }
      } else if (o.k === 'A') { for (const c of arcToCurves(o)) { add(c.end); add(c.c1); add(c.c2); } }
      if (o.end) prev = o.end;
    }
    if (x0 === Infinity) return new CGRect(Infinity, Infinity, 0, 0);
    return new CGRect(x0, y0, x1 - x0, y1 - y0);
  }
  /** Swift `path.contains(p, eoFill: false)`. */
  contains(p, eoFill = false) {
    const g = scratchContext();
    g.setTransform(1, 0, 0, 1, 0, 0);
    return g.isPointInPath(this.path2D(), p.x, p.y, eoFill ? 'evenodd' : 'nonzero');
  }
  /** Swift `path.trimmedPath(from:to:)` (approximate: by sampled length). */
  trimmedPath(from, to) {
    const pts = this._flatten();
    const q = new Path();
    for (const sub of pts) {
      let total = 0; const lens = [0];
      for (let i = 1; i < sub.length; i++) { total += Math.hypot(sub[i].x - sub[i - 1].x, sub[i].y - sub[i - 1].y); lens.push(total); }
      if (total <= 0) continue;
      const a = from * total, b = to * total; let started = false;
      for (let i = 1; i < sub.length; i++) {
        const l0 = lens[i - 1], l1 = lens[i]; if (l1 < a || l0 > b) continue;
        const at = (L) => { const k = l1 > l0 ? (L - l0) / (l1 - l0) : 0; return new CGPoint(lerp(sub[i - 1].x, sub[i].x, k), lerp(sub[i - 1].y, sub[i].y, k)); };
        if (!started) { q.move(at(Math.max(a, l0))); started = true; }
        q.addLine(at(Math.min(b, l1)));
      }
    }
    return q;
  }
  _flatten() {
    const subs = []; let cur = null, prev = null, start = null;
    for (const o of this.ops) {
      if (o.k === 'M') { cur = [o.end]; subs.push(cur); start = o.end; }
      else if (o.k === 'L') cur.push(o.end);
      else if (o.k === 'Q') for (let i = 1; i <= 16; i++) { const t = i / 16, u = 1 - t; cur.push(new CGPoint(u * u * prev.x + 2 * u * t * o.c.x + t * t * o.end.x, u * u * prev.y + 2 * u * t * o.c.y + t * t * o.end.y)); }
      else if (o.k === 'C') for (let i = 1; i <= 16; i++) { const t = i / 16, u = 1 - t; cur.push(new CGPoint(u * u * u * prev.x + 3 * u * u * t * o.c1.x + 3 * u * t * t * o.c2.x + t * t * t * o.end.x, u * u * u * prev.y + 3 * u * u * t * o.c1.y + 3 * u * t * t * o.c2.y + t * t * t * o.end.y)); }
      else if (o.k === 'A') { const n = 24; let d = o.a1 - o.a0; d = normSweep(d, o.ccw); for (let i = 1; i <= n; i++) { const a = o.a0 + d * i / n; cur.push(new CGPoint(o.center.x + o.radius * Math.cos(a), o.center.y + o.radius * Math.sin(a))); } }
      else if (o.k === 'Z' && cur && start) cur.push(start);
      if (o.end) prev = o.end;
    }
    return subs;
  }
  path2D() {
    if (this._p2d) return this._p2d;
    const p = new Path2D();
    for (const o of this.ops) {
      switch (o.k) {
        case 'M': p.moveTo(o.end.x, o.end.y); break;
        case 'L': p.lineTo(o.end.x, o.end.y); break;
        case 'Q': p.quadraticCurveTo(o.c.x, o.c.y, o.end.x, o.end.y); break;
        case 'C': p.bezierCurveTo(o.c1.x, o.c1.y, o.c2.x, o.c2.y, o.end.x, o.end.y); break;
        case 'A': p.arc(o.center.x, o.center.y, Math.abs(o.radius), o.a0, o.a1, o.ccw); break;
        case 'Z': p.closePath(); break;
      }
    }
    this._p2d = p;
    return p;
  }
}

// Sweep of an arc the way canvas draws it (CoreGraphics agrees for sweeps below a full turn).
function normSweep(d, ccw) {
  const T = Math.PI * 2;
  if (!ccw) { if (d >= T) return T; d = ((d % T) + T) % T; return d; }
  if (d <= -T) return -T; d = -(((-d % T) + T) % T); return d;
}
function arcToCurves(o) {
  const sweep = normSweep(o.a1 - o.a0, o.ccw);
  const n = Math.max(1, Math.ceil(Math.abs(sweep) / (Math.PI / 2)));
  const out = [], step = sweep / n, k = (4 / 3) * Math.tan(step / 4), { x: cx, y: cy } = o.center, r = o.radius;
  for (let i = 0; i < n; i++) {
    const a = o.a0 + step * i, b = a + step;
    out.push({ c1: new CGPoint(cx + r * (Math.cos(a) - k * Math.sin(a)), cy + r * (Math.sin(a) + k * Math.cos(a))),
      c2: new CGPoint(cx + r * (Math.cos(b) + k * Math.sin(b)), cy + r * (Math.sin(b) - k * Math.cos(b))),
      end: new CGPoint(cx + r * Math.cos(b), cy + r * Math.sin(b)) });
  }
  return out;
}

let _scratch = null;
function scratchContext() {
  if (!_scratch) _scratch = new OffscreenCanvas(4, 4).getContext('2d');
  return _scratch;
}

// MARK: - Shading, gradients, filters, styles (GraphicsContext.Shading / Filter, StrokeStyle)

/** SwiftUI Gradient: Gradient.colors([a, b]) = `Gradient(colors: [a.color, b.color])`;
 *  Gradient.stops([[a, 0], [b, 0.7]]) = `Gradient(stops: [.init(color: a.color, location: 0), ...])`. */
export class Gradient {
  constructor(stops) { this.stops = stops; }
  static colors(cs) { return new Gradient(cs.map((c, i) => [c, cs.length > 1 ? i / (cs.length - 1) : 0])); }
  static stops(ss) { return new Gradient(ss.map((s) => (Array.isArray(s) ? s : [s.color, s.location]))); }
}
function asGradient(g) {
  if (g instanceof Gradient) return g;
  if (Array.isArray(g)) return Array.isArray(g[0]) ? Gradient.stops(g) : Gradient.colors(g);
  throw new Error('expected a Gradient (Gradient.colors([...]) or Gradient.stops([...]))');
}

export const Shading = {
  color: (c) => ({ kind: 'color', c }),
  linearGradient: (g, startPoint, endPoint) => ({ kind: 'linear', g: asGradient(g), startPoint, endPoint }),
  radialGradient: (g, center, startRadius, endRadius) => ({ kind: 'radial', g: asGradient(g), center, startRadius, endRadius }),
  /** angle (radians): where the gradient starts, 0 = pointing right (+x), turning clockwise on screen. */
  conicGradient: (g, center, angle = 0) => ({ kind: 'conic', g: asGradient(g), center, angle }),
};

export const Filter = {
  blur: (radius) => ({ kind: 'blur', radius }),
  /** opts.shadowOnly: Swift `options: .shadowOnly` (draw only the shadow, not the shape). */
  shadow: (color, radius, x = 0, y = 0, opts = {}) => ({ kind: 'shadow', color, radius, x, y, shadowOnly: !!opts.shadowOnly }),
  brightness: (amount) => ({ kind: 'brightness', amount }),
  contrast: (amount) => ({ kind: 'contrast', amount }),
  saturation: (amount) => ({ kind: 'saturation', amount }),
  hueRotation: (angle) => ({ kind: 'hueRotation', angle }),
  grayscale: (amount) => ({ kind: 'grayscale', amount }),
  colorInvert: (amount = 1) => ({ kind: 'colorInvert', amount }),
  /** Swift `.colorMultiply(c.color)`. */
  colorMultiply: (color) => ({ kind: 'colorMultiply', color }),
  /** Swift `.alphaThreshold(min: a, max: b, color: c.color)`: alpha within [min, max] → the colour, else clear. */
  alphaThreshold: (min, max = 1, color = RGBA.black) => ({ kind: 'alphaThreshold', min, max, color }),
  /** Swift `.colorMatrix(m)`: 20 numbers, rows r, g, b, a; each row: ×r ×g ×b ×a +offset (offset in 0…1). */
  colorMatrix: (m) => { if (m.length !== 20) throw new Error('colorMatrix needs 20 numbers'); return { kind: 'colorMatrix', m }; },
};

const BLEND = {
  normal: 'source-over', multiply: 'multiply', screen: 'screen', overlay: 'overlay', darken: 'darken', lighten: 'lighten',
  colorDodge: 'color-dodge', colorBurn: 'color-burn', softLight: 'soft-light', hardLight: 'hard-light',
  difference: 'difference', exclusion: 'exclusion', hue: 'hue', saturation: 'saturation', color: 'color', luminosity: 'luminosity',
  plusLighter: 'lighter', copy: 'copy', sourceIn: 'source-in', sourceOut: 'source-out', sourceAtop: 'source-atop',
  destinationOver: 'destination-over', destinationIn: 'destination-in', destinationOut: 'destination-out',
  destinationAtop: 'destination-atop', xor: 'xor', clear: 'destination-out',
};
export const BlendModes = Object.keys(BLEND);

export const UnitPoint = {
  topLeading: { x: 0, y: 0 }, top: { x: 0.5, y: 0 }, topTrailing: { x: 1, y: 0 },
  leading: { x: 0, y: 0.5 }, center: { x: 0.5, y: 0.5 }, trailing: { x: 1, y: 0.5 },
  bottomLeading: { x: 0, y: 1 }, bottom: { x: 0.5, y: 1 }, bottomTrailing: { x: 1, y: 1 },
};

// MARK: - Text

const FONT_FAMILIES = {
  default: '"SF Pro Text", "Helvetica Neue", "Liberation Sans", "Noto Sans", "Noto Sans CJK JP", sans-serif',
  monospaced: '"SF Mono", Menlo, "DejaVu Sans Mono", "Noto Sans Mono CJK JP", monospace',
  rounded: '"SF Pro Rounded", "Nunito", "Lato", "Noto Sans CJK JP", sans-serif',
  serif: '"New York", Georgia, "Liberation Serif", "Noto Serif CJK JP", serif',
};
const WEIGHTS = { ultraLight: 100, thin: 200, light: 300, regular: 400, medium: 500, semibold: 600, bold: 700, heavy: 800, black: 900 };

export class ResolvedText {
  constructor(string, opts) {
    this.string = String(string);
    this.size = opts.size ?? 13;
    this.weight = opts.weight ?? 'regular';
    this.design = opts.design ?? 'default';
    this.color = opts.color ?? RGBA.black;
    this.font = `${WEIGHTS[this.weight] ?? 400} ${this.size}px ${opts.family ? `"${opts.family}", ` : ''}${FONT_FAMILIES[this.design] ?? FONT_FAMILIES.default}`;
    const g = scratchContext();
    g.font = this.font;
    const m = g.measureText(this.string);
    this.width = m.width;
    // SwiftUI anchors text by its line box (ascent + descent of the font), not by the ink.
    this.ascent = m.fontBoundingBoxAscent ?? this.size * 0.95;
    this.descent = m.fontBoundingBoxDescent ?? this.size * 0.25;
  }
  /** Swift `resolved.measure(in: CGSize)`: the size of the line box. */
  measure() { return new CGSize(this.width, this.ascent + this.descent); }
}

// MARK: - GraphicsContext

const STATS = { fill: 0, stroke: 0, drawPad: 0, text: 0, layer: 0, blurred: 0 };
export function resetStats() { for (const k in STATS) STATS[k] = 0; }
export function getStats() { return { ...STATS }; }

const SVGNS = 'http://www.w3.org/2000/svg';
function svgEl(name, attrs = {}, kids = []) {
  const e = document.createElementNS(SVGNS, name);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, String(v));
  for (const k of kids) e.appendChild(k);
  return e;
}
/** Builds (once) an SVG filter for things CSS filters cannot do, and returns its url(#id). */
function svgFilter(kind, value) {
  const key = 'fx-' + kind + '-' + JSON.stringify(value).replace(/[^a-zA-Z0-9.-]/g, '_');
  if (typeof document === 'undefined') return '';
  if (document.getElementById(key)) return `url(#${key})`;
  let svg = document.getElementById('fx-svg-defs');
  if (!svg) {
    svg = svgEl('svg', { id: 'fx-svg-defs', width: 0, height: 0 });
    svg.style.position = 'absolute';
    document.body.appendChild(svg);
  }
  const lin = (ch, slope, intercept) => svgEl('feFunc' + ch, { type: 'linear', slope, intercept });
  let kids;
  if (kind === 'brightness') {
    // Swift's brightness adds `amount` to every channel; CSS brightness() multiplies.
    kids = [svgEl('feComponentTransfer', {}, [lin('R', 1, value), lin('G', 1, value), lin('B', 1, value)])];
  } else if (kind === 'mul') {
    kids = [svgEl('feComponentTransfer', {}, [lin('R', value.r, 0), lin('G', value.g, 0), lin('B', value.b, 0), lin('A', value.a, 0)])];
  } else if (kind === 'matrix') {
    kids = [svgEl('feColorMatrix', { type: 'matrix', values: value.join(' ') })];
  } else if (kind === 'threshold') {
    // Alpha inside [min, max] becomes the colour (fully opaque colour times its own alpha), anything else clear.
    const n = 256, table = [];
    for (let i = 0; i < n; i++) { const a = i / (n - 1); table.push(a >= value.min && a <= value.max ? 1 : 0); }
    kids = [
      svgEl('feComponentTransfer', { in: 'SourceGraphic', result: 'mask' }, [svgEl('feFuncA', { type: 'discrete', tableValues: table.join(' ') })]),
      svgEl('feFlood', { 'flood-color': `rgb(${value.c[0]},${value.c[1]},${value.c[2]})`, 'flood-opacity': value.c[3], result: 'fill' }),
      svgEl('feComposite', { in: 'fill', in2: 'mask', operator: 'in' }),
    ];
  } else if (kind === 'shadowOnly') {
    kids = [
      svgEl('feGaussianBlur', { in: 'SourceAlpha', stdDeviation: value.r, result: 'b' }),
      svgEl('feOffset', { in: 'b', dx: value.x, dy: value.y, result: 'o' }),
      svgEl('feFlood', { 'flood-color': `rgb(${value.c[0]},${value.c[1]},${value.c[2]})`, 'flood-opacity': value.c[3], result: 'f' }),
      svgEl('feComposite', { in: 'f', in2: 'o', operator: 'in' }),
    ];
  }
  svg.appendChild(svgEl('filter', { id: key, 'color-interpolation-filters': 'sRGB', x: '-50%', y: '-50%', width: '200%', height: '200%',
    filterUnits: 'objectBoundingBox' }, kids));
  return `url(#${key})`;
}
const c255 = (c) => [Math.round(clamp01(c.r) * 255), Math.round(clamp01(c.g) * 255), Math.round(clamp01(c.b) * 255), clamp01(c.a)];

function matScale(m) { return Math.sqrt(Math.abs(m.a * m.d - m.b * m.c)); }
function toDOM(m) { return new DOMMatrix([m.a, m.b, m.c, m.d, m.tx, m.ty]); }

/** A canvas in the page's document when there is one (SVG filters only work there), else an OffscreenCanvas. */
export function makeCanvas(w, h) {
  if (typeof document !== 'undefined') { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
  return new OffscreenCanvas(w, h);
}

/** Pool of full-size scratch canvases for layers. */
export class LayerPool {
  constructor(w, h) { this.w = w; this.h = h; this.free = []; }
  get() {
    const c = this.free.pop() || makeCanvas(this.w, this.h);
    const g = c.getContext('2d');
    g.setTransform(1, 0, 0, 1, 0, 0); g.globalAlpha = 1; g.globalCompositeOperation = 'source-over'; g.filter = 'none';
    g.clearRect(0, 0, this.w, this.h);
    return c;
  }
  put(c) { this.free.push(c); }
}

/**
 * SwiftUI.GraphicsContext as a value type. `const g = ctx.copy()` is Swift's `var g = ctx`: the copy has its
 * own opacity, blendMode, clip, filters and transform; changing it never affects ctx.
 */
export class Ctx {
  constructor(target, pool, transform) {
    this._t = target;          // CanvasRenderingContext2D / OffscreenCanvasRenderingContext2D
    this._pool = pool;
    this.transform = transform; // CGAffineTransform from user points to device pixels
    this.opacity = 1;
    this.blendMode = 'normal';
    this._filters = [];
    this._clips = [];           // { path, transform, eo, inverse }
    this._masks = [];           // { canvas, opacity }
  }
  copy() {
    const c = new Ctx(this._t, this._pool, this.transform);
    c.opacity = this.opacity; c.blendMode = this.blendMode;
    c._filters = this._filters.slice(); c._clips = this._clips.slice(); c._masks = this._masks.slice();
    return c;
  }

  // Transform (applies to later drawing, in the current local space)
  translateBy(x, y) { this.transform = CGAffineTransform.translation(x, y).concatenating(this.transform); }
  scaleBy(x, y) { this.transform = CGAffineTransform.scale(x, y).concatenating(this.transform); }
  rotate(by) { this.transform = CGAffineTransform.rotation(by).concatenating(this.transform); }
  concatenate(m) { this.transform = m.concatenating(this.transform); }

  // Clip and filters
  /** Swift `ctx.clip(to: path, style: FillStyle(eoFill:), options: .inverse)`: opts = { eoFill, inverse }. */
  clip(path, opts = {}) { this._clips = this._clips.concat([{ path, transform: this.transform, eo: !!opts.eoFill, inverse: !!opts.inverse }]); }
  /** Swift `ctx.clipToLayer(opacity:options:) { layer in ... }`: later drawing only shows where the layer has alpha. */
  clipToLayer(fn, opts = {}) {
    const canvas = this._pool.get();
    const layer = new Ctx(canvas.getContext('2d'), this._pool, this.transform);
    fn(layer);
    this._masks = this._masks.concat([{ canvas, opacity: opts.opacity ?? 1, inverse: !!opts.inverse }]);
  }
  addFilter(f) { this._filters = this._filters.concat([f]); }

  _filterString(scale) {
    if (!this._filters.length) return 'none';
    const parts = [];
    for (const f of this._filters) {
      switch (f.kind) {
        // SwiftUI's blur radius is treated as the Gaussian's standard deviation, the same as CSS blur().
        // Checked against the Mac: see PORTING.md, "Blur radius".
        case 'blur': parts.push(`blur(${Math.max(0, f.radius * scale)}px)`); break;
        case 'shadow':
          if (f.shadowOnly) parts.push(svgFilter('shadowOnly', { r: f.radius * scale, x: f.x * scale, y: f.y * scale, c: c255(f.color) }));
          else parts.push(`drop-shadow(${f.x * scale}px ${f.y * scale}px ${f.radius * scale}px ${f.color.css()})`);
          break;
        case 'alphaThreshold': parts.push(svgFilter('threshold', { min: f.min, max: f.max, c: c255(f.color) })); break;
        case 'colorMatrix': parts.push(svgFilter('matrix', f.m)); break;
        case 'brightness': parts.push(svgFilter('brightness', f.amount)); break;
        case 'contrast': parts.push(`contrast(${f.amount})`); break;
        case 'saturation': parts.push(`saturate(${f.amount})`); break;
        case 'hueRotation': parts.push(`hue-rotate(${f.angle}rad)`); break;
        case 'grayscale': parts.push(`grayscale(${f.amount})`); break;
        case 'colorInvert': parts.push(`invert(${f.amount})`); break;
        case 'colorMultiply': parts.push(svgFilter('mul', { r: f.color.r, g: f.color.g, b: f.color.b, a: f.color.a })); break;
      }
    }
    return parts.join(' ');
  }
  _hasBlur() { return this._filters.some((f) => f.kind === 'blur' || f.kind === 'shadow'); }

  _applyClips(g) {
    for (const c of this._clips) {
      g.setTransform(toDOM(c.transform));
      if (c.inverse) {
        const p = new Path2D();
        const inv = c.transform.inverted();
        // A huge rectangle around everything, in the clip's own space, with the path cut out of it.
        const W = g.canvas.width, H = g.canvas.height;
        const pts = [[0, 0], [W, 0], [W, H], [0, H]].map(([x, y]) => inv.apply(new CGPoint(x, y)));
        const xs = pts.map((q) => q.x), ys = pts.map((q) => q.y);
        const x0 = Math.min(...xs) - 10, y0 = Math.min(...ys) - 10, x1 = Math.max(...xs) + 10, y1 = Math.max(...ys) + 10;
        p.addPath(c.path.path2D());
        p.rect(x0, y0, x1 - x0, y1 - y0);
        // Even-odd of (path + big rect) is the outside of the path (for simple non-self-overlapping paths).
        g.clip(p, 'evenodd');
      } else g.clip(c.path.path2D(), c.eo ? 'evenodd' : 'nonzero');
    }
  }

  _style(g, shading) {
    if (!shading || !shading.kind) throw new Error('expected a Shading, e.g. Shading.color(c) (Swift: .color(c.color))');
    switch (shading.kind) {
      case 'color': return shading.c.css();
      case 'linear': { const s = g.createLinearGradient(shading.startPoint.x, shading.startPoint.y, shading.endPoint.x, shading.endPoint.y); addStops(s, shading.g); return s; }
      case 'radial': { const c = shading.center; const s = g.createRadialGradient(c.x, c.y, Math.max(0, shading.startRadius), c.x, c.y, Math.max(0, shading.endRadius)); addStops(s, shading.g); return s; }
      case 'conic': { const s = g.createConicGradient(shading.angle, shading.center.x, shading.center.y); addStops(s, shading.g); return s; }
    }
  }

  /** Runs one drawing operation with this context's state, on the real canvas. */
  _draw(op) {
    if (this.opacity <= 0) return;
    if (this._hasBlur()) STATS.blurred++;
    const scale = matScale(this.transform);
    if (this._masks.length) {
      // Draw into a scratch layer, keep only what the masks allow, then composite.
      const tmp = this._pool.get();
      const tg = tmp.getContext('2d');
      tg.save();
      tg.filter = this._filterString(scale);
      tg.setTransform(toDOM(this.transform));
      op(tg);
      tg.restore();
      for (const m of this._masks) {
        tg.save(); tg.setTransform(1, 0, 0, 1, 0, 0);
        tg.globalAlpha = m.opacity; tg.globalCompositeOperation = m.inverse ? 'destination-out' : 'destination-in';
        tg.drawImage(m.canvas, 0, 0); tg.restore();
      }
      const g = this._t;
      g.save();
      this._applyClips(g);
      g.setTransform(1, 0, 0, 1, 0, 0);
      g.globalAlpha = clamp01(this.opacity);
      g.globalCompositeOperation = BLEND[this.blendMode] || 'source-over';
      g.drawImage(tmp, 0, 0);
      g.restore();
      this._pool.put(tmp);
      return;
    }
    const g = this._t;
    g.save();
    this._applyClips(g);
    g.globalAlpha = clamp01(this.opacity);
    g.globalCompositeOperation = BLEND[this.blendMode] || 'source-over';
    g.filter = this._filterString(scale);
    g.setTransform(toDOM(this.transform));
    op(g);
    g.restore();
  }

  /** Swift `ctx.fill(path, with: shading, style: FillStyle(eoFill:))`. */
  fill(path, shading, style = {}) {
    STATS.fill++;
    this._draw((g) => { g.fillStyle = this._style(g, shading); g.fill(path.path2D(), style.eoFill ? 'evenodd' : 'nonzero'); });
  }
  /** Swift `ctx.stroke(path, with: shading, lineWidth: w)` or `..., style: StrokeStyle(lineWidth:, lineCap:, lineJoin:, miterLimit:, dash:, dashPhase:)`. */
  stroke(path, shading, style = 1) {
    STATS.stroke++;
    const s = typeof style === 'number' ? { lineWidth: style } : style;
    this._draw((g) => {
      g.strokeStyle = this._style(g, shading);
      g.lineWidth = s.lineWidth ?? 1;
      g.lineCap = s.lineCap ?? 'butt';
      g.lineJoin = s.lineJoin ?? 'miter';
      g.miterLimit = s.miterLimit ?? 10;
      if (s.dash) { g.setLineDash(s.dash); g.lineDashOffset = s.dashPhase ?? 0; }
      g.stroke(path.path2D());
    });
  }
  /** Swift `ctx.drawLayer { layer in ... }`: draws a group, then composites it with this context's opacity, blend, filters and clip. */
  drawLayer(fn) {
    STATS.layer++;
    if (this.opacity <= 0) return;
    const canvas = this._pool.get();
    const layer = new Ctx(canvas.getContext('2d'), this._pool, this.transform);
    fn(layer);
    const scale = matScale(this.transform);
    if (this._hasBlur()) STATS.blurred++;
    const g = this._t;
    g.save();
    this._applyClips(g);
    g.globalAlpha = clamp01(this.opacity);
    g.globalCompositeOperation = BLEND[this.blendMode] || 'source-over';
    g.filter = this._filterString(scale);
    g.setTransform(1, 0, 0, 1, 0, 0);
    if (this._masks.length) {
      const lg = canvas.getContext('2d');
      for (const m of this._masks) {
        lg.save(); lg.setTransform(1, 0, 0, 1, 0, 0); lg.globalAlpha = m.opacity;
        lg.globalCompositeOperation = m.inverse ? 'destination-out' : 'destination-in'; lg.drawImage(m.canvas, 0, 0); lg.restore();
      }
    }
    g.drawImage(canvas, 0, 0);
    g.restore();
    this._pool.put(canvas);
  }
  /** Draws an image-like source (canvas) in a rect. Used by drawPad; Swift: `ctx.draw(image, in: rect)`. */
  drawImage(source, rect) {
    if (rect.width === 0 || rect.height === 0) return;
    this._draw((g) => { g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high'; g.drawImage(source, rect.x, rect.y, rect.width, rect.height); });
  }
  /** Swift `ctx.resolve(Text(s).font(.system(size:, weight:, design:)).foregroundColor(c.color))`. */
  resolveText(string, opts = {}) { return new ResolvedText(string, opts); }
  resolve(text) { return text instanceof ResolvedText ? text : new ResolvedText(String(text), {}); }
  /** Swift `ctx.draw(resolved, at: p, anchor: .center)`. anchor: a UnitPoint name ('center', 'topLeading', ...) or {x, y}. */
  drawText(resolved, at, anchor = 'center') {
    STATS.text++;
    const a = typeof anchor === 'string' ? UnitPoint[anchor] : anchor;
    if (!a) throw new Error(`unknown anchor ${anchor}`);
    const h = resolved.ascent + resolved.descent;
    const x = at.x - a.x * resolved.width, top = at.y - a.y * h;
    this._draw((g) => {
      g.font = resolved.font; g.textBaseline = 'alphabetic'; g.textAlign = 'left';
      g.fillStyle = resolved.color.css();
      g.fillText(resolved.string, x, top + resolved.ascent);
    });
  }
  /** Swift `ctx.draw(resolved, in: rect)`: the text's line box placed at the rect's top-left. */
  drawTextIn(resolved, rect) { this.drawText(resolved, new CGPoint(rect.minX, rect.minY), 'topLeading'); }
}
function addStops(s, g) { for (const [c, loc] of g.stops) s.addColorStop(clamp01(loc), c.css()); }

// MARK: - Pad pictures, cells, frames

/** Docked: flat top that flares into the menu bar, round bottom corners. Floating: a rounded card. */
export function closePadPath(r, floating) {
  if (floating) {
    const radius = Math.min(18, r.width / 2, r.height / 2);
    return Path.roundedRect(r, Math.max(0, radius), 'continuous');
  }
  const t = Math.max(0, Math.min(12, r.width / 4, r.height / 2));
  const b = Math.max(0, Math.min(22, (r.width - 2 * t) / 2, r.height - t));
  const P = (x, y) => new CGPoint(x, y);
  const p = new Path();
  p.move(P(r.minX, r.minY));
  p.addQuadCurve(P(r.minX + t, r.minY + t), P(r.minX + t, r.minY));
  p.addLine(P(r.minX + t, r.maxY - b));
  p.addQuadCurve(P(r.minX + t + b, r.maxY), P(r.minX + t, r.maxY));
  p.addLine(P(r.maxX - t - b, r.maxY));
  p.addQuadCurve(P(r.maxX - t, r.maxY - b), P(r.maxX - t, r.maxY));
  p.addLine(P(r.maxX - t, r.minY + t));
  p.addQuadCurve(P(r.maxX, r.minY), P(r.maxX - t, r.minY));
  p.closeSubpath();
  return p;
}

/** The same flared outline as the docked pad, with chosen top flare and bottom corner sizes. */
export function notchShapePath(r, top, bottom) {
  const t = Math.max(0, Math.min(top, r.width / 4, r.height / 2));
  const b = Math.max(0, Math.min(bottom, (r.width - 2 * t) / 2, r.height - t));
  const P = (x, y) => new CGPoint(x, y);
  const p = new Path();
  p.move(P(r.minX, r.minY));
  p.addQuadCurve(P(r.minX + t, r.minY + t), P(r.minX + t, r.minY));
  p.addLine(P(r.minX + t, r.maxY - b));
  p.addQuadCurve(P(r.minX + t + b, r.maxY), P(r.minX + t, r.maxY));
  p.addLine(P(r.maxX - t - b, r.maxY));
  p.addQuadCurve(P(r.maxX - t, r.maxY - b), P(r.maxX - t, r.maxY));
  p.addLine(P(r.maxX - t, r.minY + t));
  p.addQuadCurve(P(r.maxX, r.minY), P(r.maxX - t, r.minY));
  p.closeSubpath();
  return p;
}

/** Like Swift's FlightEffectCanvas: a black notch drawn under the effect while 0 < t < 1, fading in and out. */
export function drawFlightNotch(ctx, f) {
  if (f.t <= 0 || f.t >= 1) return;
  const a = smoothstep(0, 0.12, f.t) * (1 - smoothstep(0.88, 1, f.t));
  if (a <= 0) return;
  const r = new CGRect(f.notch.minX - 6, f.notch.minY, f.notch.width + 12, f.notch.height);
  ctx.fill(notchShapePath(r, 6, 9), Shading.color(RGBA.black.alpha(a)));
}

export class CloseCells {
  constructor(cols, rows, size, origin, data) { this.cols = cols; this.rows = rows; this.size = size; this._origin = origin; this._data = data; }
  /** Average colour of that cell (alpha 0 where the pad has no pixels). */
  color(col, row) {
    if (col < 0 || row < 0 || col >= this.cols || row >= this.rows) return RGBA.clear;
    const i = (row * this.cols + col) * 4, d = this._data;
    if (i + 3 >= d.length) return RGBA.clear;
    const a = d[i + 3] / 255;
    if (a <= 0) return RGBA.clear;
    return new RGBA(Math.min(1, d[i] / 255 / a), Math.min(1, d[i + 1] / 255 / a), Math.min(1, d[i + 2] / 255 / a), a);
  }
  rect(col, row) { return new CGRect(this._origin.x + col * this.size, this._origin.y + row * this.size, this.size, this.size); }
}

/** Swift CloseScene.makeCells: one cell = one pixel of the picture shrunk to cols × rows (premultiplied, row 0 at top). */
export function makeCells(picture, pad) {
  const size = Math.max(6, Math.sqrt(pad.width * pad.height / 5000));
  const cols = Math.max(1, Math.ceil(pad.width / size));
  const rows = Math.max(1, Math.ceil(pad.height / size));
  const w = pad.width / size, h = pad.height / size;
  // Shrink in halving steps (an area average, close to CoreGraphics' medium-quality downscale).
  let src = picture, sw = picture.width, sh = picture.height;
  const tw = Math.max(1, Math.round(w * 8)), th = Math.max(1, Math.round(h * 8));
  while (sw / 2 >= tw && sh / 2 >= th) {
    const nw = Math.round(sw / 2), nh = Math.round(sh / 2);
    const c = new OffscreenCanvas(nw, nh), g = c.getContext('2d');
    g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
    g.drawImage(src, 0, 0, sw, sh, 0, 0, nw, nh);
    src = c; sw = nw; sh = nh;
  }
  const c = new OffscreenCanvas(cols, rows), g = c.getContext('2d', { willReadFrequently: true });
  g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
  g.drawImage(src, 0, 0, sw, sh, 0, 0, w, h);
  const img = g.getImageData(0, 0, cols, rows).data; // un-premultiplied RGBA
  const data = new Uint8ClampedArray(cols * rows * 4);
  for (let i = 0; i < cols * rows; i++) {
    const a = img[i * 4 + 3];
    data[i * 4] = Math.round(img[i * 4] * a / 255); data[i * 4 + 1] = Math.round(img[i * 4 + 1] * a / 255);
    data[i * 4 + 2] = Math.round(img[i * 4 + 2] * a / 255); data[i * 4 + 3] = a;
  }
  return new CloseCells(cols, rows, size, pad.origin, data);
}

export class CloseFrame {
  constructor(o) { Object.assign(this, o); }
  get seconds() { return this.t * this.duration; }
  get target() { return new CGPoint(this.sink.midX, this.sink.midY); }
  get padPath() { return this.padPathIn(this.pad); }
  /** Swift `f.padPath(in: rect)`. */
  padPathIn(rect) { return closePadPath(rect, this.floating); }
  /** Swift `f.drawPad(ctx, in: rect, opacity: x)`. */
  drawPad(ctx, rect = null, opacity = 1) {
    STATS.drawPad++;
    if (opacity <= 0) return;
    const c = ctx.copy();
    if (opacity < 1) c.opacity = c.opacity * opacity;
    c.drawImage(this._image, rect || this.pad);
  }
}

export class FlightFrame {
  constructor(o) { Object.assign(this, o); }
  get seconds() { return this.t * this.duration; }
  /** Centre to centre, in points. */
  get distance() { return Math.hypot(this.to.midX - this.from.midX, this.to.midY - this.from.midY); }
  get fromPath() { return closePadPath(this.from, true); }
  get toPath() { return closePadPath(this.to, false); }
  /** Swift `f.fromPath(in: rect)` / `f.toPath(in: rect)`. */
  fromPathIn(rect) { return closePadPath(rect, true); }
  toPathIn(rect) { return closePadPath(rect, false); }
  /** Swift `f.drawFrom(ctx, in: rect, opacity: x)`: the floating card's picture. */
  drawFrom(ctx, rect = null, opacity = 1) {
    STATS.drawPad++;
    if (opacity <= 0) return;
    const c = ctx.copy();
    if (opacity < 1) c.opacity = c.opacity * opacity;
    c.drawImage(this._fromImage, rect || this.from);
  }
  /** Swift `f.drawTo(ctx, in: rect, opacity: x)`: the docked pad's picture. */
  drawTo(ctx, rect = null, opacity = 1) {
    STATS.drawPad++;
    if (opacity <= 0) return;
    const c = ctx.copy();
    if (opacity < 1) c.opacity = c.opacity * opacity;
    c.drawImage(this._toImage, rect || this.to);
  }
}

// MARK: - Mock scenes (CloseScene.mock and the flight mock)

export const BLEED = 160;
export const DEFAULT_SEED = 20261128;
const MOCK_LINES = ['Things to remember', '', 'Call the plumber about the tap', 'milk, eggs, coffee, bread',
  'Wi-Fi at the bach: kowhai-5G', 'Ideas for the deck: wider steps,', 'a seat along the fence, lights',
  'Book the ferry for Friday', 'Ring Mum on Sunday'];

export function themeFromSpec(spec) {
  const bg = RGBA.hex(spec.background), text = RGBA.hex(spec.text), accent = RGBA.hex(spec.accent);
  const lum = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b;
  return { ...spec, bg, textColor: text, accentColor: accent, dark: lum < 0.5 };
}

function themeFont(theme, size) {
  const fb = theme.fallback || 'system';
  const design = fb === 'mono' ? 'monospaced' : fb === 'serif' ? 'serif' : fb === 'rounded' ? 'rounded' : 'default';
  const face = theme.face || 'regular';
  const weight = { light: 300, medium: 500, semibold: 600, bold: 700, boldItalic: 700 }[face] || 400;
  const italic = /italic/i.test(face) || (theme.fonts || []).some((f) => /italic/i.test(f)) ? 'italic ' : '';
  const scaled = size * (theme.scale || 1);
  return { css: `${italic}${weight} ${scaled}px ${FONT_FAMILIES[design]}`, tracking: theme.tracking || 0 };
}

/** The stand-in picture of the pad, drawn like Swift's CloseScene.mock (2× pixels). */
export function mockPadPicture(theme, padSize, floating, scale = 2) {
  const c = new OffscreenCanvas(Math.ceil(padSize.width * scale), Math.ceil(padSize.height * scale));
  const g = c.getContext('2d');
  g.scale(scale, scale);
  const local = new CGRect(0, 0, padSize.width, padSize.height);
  g.clip(closePadPath(local, floating).path2D());
  g.fillStyle = theme.bg.css();
  g.fillRect(0, 0, padSize.width, padSize.height);
  const top = floating ? 8 : 34, left = floating ? 16 : 24, right = padSize.width - (floating ? 16 : 24);
  const dim = theme.textColor.alpha(0.55).css(), accent = theme.accentColor.css();
  for (let i = 0; i < 4; i++) {
    g.fillStyle = dim; g.fillRect(left + i * 24, top + 3, 13, 13);
    g.fillStyle = i === 3 ? accent : dim; g.fillRect(right - 13 - i * 24, top + 3, 13, 13);
  }
  const f = themeFont(theme, 13);
  g.font = f.css; g.fillStyle = theme.textColor.css(); g.textBaseline = 'alphabetic';
  if (f.tracking) g.letterSpacing = `${f.tracking}px`;
  if (theme.glow) { g.shadowColor = RGBA.hex(theme.glow).alpha(0.33).css(); g.shadowBlur = 3 * scale; }
  const m = g.measureText('Hg');
  const ascent = m.fontBoundingBoxAscent ?? 12;
  let y = top + 28;
  for (const line of MOCK_LINES) {
    if (y > padSize.height - 30) break;
    if (line) g.fillText(line, left + 4, y + ascent);
    y += 19;
  }
  return c;
}

/** Swift `CloseScene.mock(effect:theme:padSize:floating:seed:)`, as a frame factory. */
export function closeScene({ theme, padSize = new CGSize(500, 290), floating = false, seed = DEFAULT_SEED, duration, speed = 1 }) {
  const bleed = BLEED;
  const size = new CGSize(padSize.width + 2 * bleed, padSize.height + bleed + (floating ? bleed : 0));
  const pad = new CGRect(bleed, floating ? bleed : 0, padSize.width, padSize.height);
  const sink = floating ? new CGRect(pad.midX - 20, pad.midY - 3, 40, 6) : new CGRect(pad.midX - 90, 0, 180, 32);
  const picture = mockPadPicture(theme, padSize, floating);
  const cells = makeCells(picture, pad);
  const dur = Math.max(0.15, duration * speed);
  return {
    kind: 'close', size, pad, sink, floating, focus: pad,
    frame: (t) => new CloseFrame({ t: clamp01(t), duration: dur, size, pad, sink, floating, bg: theme.bg, text: theme.textColor,
      accent: theme.accentColor, dark: theme.dark, seed: seed >>> 0, cells, _image: picture }),
  };
}

/** Flight mock, agreed with Sources/FlightEffects.swift: canvas 1180 × 760, docked pad at top centre. */
export const FLIGHT_LAYOUTS = { near: [455, 172], far: [625, 440], left: [55, 268], right: [625, 268], below: [340, 440] };
export function flightScene({ theme, layout = 'far', seed = DEFAULT_SEED, duration, speed = 1 }) {
  const padSize = new CGSize(500, 290);
  const size = new CGSize(1180, 760);
  const o = FLIGHT_LAYOUTS[layout];
  if (!o) throw new Error(`unknown layout ${layout}; use ${Object.keys(FLIGHT_LAYOUTS).join('|')}`);
  const from = new CGRect(o[0], o[1], padSize.width, padSize.height);
  const to = new CGRect(340, 0, padSize.width, padSize.height);
  const notch = new CGRect(500, 0, 180, 32);
  const fromPic = mockPadPicture(theme, padSize, true), toPic = mockPadPicture(theme, padSize, false);
  const fromCells = makeCells(fromPic, from), toCells = makeCells(toPic, to);
  // Like FlightScene: longer flights take longer (0.65x for a hop, 1.2x across the screen).
  const dist = Math.hypot(to.midX - from.midX, to.midY - from.midY);
  const dur = Math.max(0.15, duration * speed * lerp(0.65, 1.2, smoothstep(24, 1100, dist)));
  return {
    kind: 'flight', size, from, to, notch, focus: from.union(to),
    frame: (t) => new FlightFrame({ t: clamp01(t), duration: dur, size, from, to, notch, bg: theme.bg, text: theme.textColor,
      accent: theme.accentColor, dark: theme.dark, seed: seed >>> 0, fromCells, toCells, _fromImage: fromPic, _toImage: toPic }),
  };
}

// MARK: - Backdrops

export function drawBackdrop(g, kind, w, h) {
  g.save();
  if (kind === 'none') { g.restore(); return; }
  if (kind === 'light') {
    // A pale desktop, like a light wallpaper with windows.
    g.setTransform(w, 0, 0, h, 0, 0);
    const lg = g.createLinearGradient(0, 0, 1, 1);
    lg.addColorStop(0, '#e9eef5'); lg.addColorStop(1, '#d6dde8');
    g.fillStyle = lg; g.fillRect(0, 0, 1, 1);
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.fillStyle = 'rgba(255,255,255,0.85)'; g.fillRect(w * 0.08, h * 0.45, w * 0.38, h * 0.45);
    g.fillStyle = 'rgba(0,0,0,0.08)'; g.fillRect(w * 0.08, h * 0.45, w * 0.38, 22);
  } else if (kind === 'photo') {
    // A busy colourful picture: animations play over the user's real desktop and must read on anything.
    g.setTransform(1, 0, 0, 1, 0, 0);
    const lg = g.createLinearGradient(0, 0, w, h);
    lg.addColorStop(0, '#ff7a59'); lg.addColorStop(0.3, '#ffd166'); lg.addColorStop(0.55, '#06d6a0');
    lg.addColorStop(0.8, '#118ab2'); lg.addColorStop(1, '#7b2cbf');
    g.fillStyle = lg; g.fillRect(0, 0, w, h);
    const blobs = [[0.2, 0.3, 0.25, '#ffffff', 0.45], [0.75, 0.25, 0.2, '#ef476f', 0.6], [0.6, 0.8, 0.3, '#073b4c', 0.55],
      [0.1, 0.85, 0.18, '#fca311', 0.6], [0.9, 0.7, 0.15, '#ffffff', 0.35], [0.45, 0.5, 0.12, '#3a0ca3', 0.5]];
    for (const [x, y, r, c, a] of blobs) {
      const rg = g.createRadialGradient(x * w, y * h, 0, x * w, y * h, r * Math.max(w, h));
      rg.addColorStop(0, c); rg.addColorStop(1, 'rgba(0,0,0,0)');
      g.globalAlpha = a; g.fillStyle = rg; g.fillRect(0, 0, w, h);
    }
    g.globalAlpha = 1;
  } else {
    // Swift's debug renderer: LinearGradient(.topLeading → .bottomTrailing). Checked against the Mac frames:
    // the gradient runs corner to corner with its bands at right angles to that line (in points, not unit space).
    g.setTransform(1, 0, 0, 1, 0, 0);
    const lg = g.createLinearGradient(0, 0, w, h);
    lg.addColorStop(0, 'rgb(28.05,33.15,51)'); lg.addColorStop(1, 'rgb(58.65,43.35,63.75)');
    g.fillStyle = lg; g.fillRect(0, 0, w, h);
  }
  g.restore();
}

// Every public name, for installing as globals in the harness page.
export const API = {
  clamp01, lerp, phase, easeIn, easeOut, easeInOut, smoothstep, closeHash, CloseRNG, closeNoise, RGBA, CGPoint, CGSize, CGRect,
  CGAffineTransform, Angle, Path, Gradient, Shading, Filter, UnitPoint, ResolvedText, Ctx, CloseCells, CloseFrame, FlightFrame,
  closePadPath, BlendModes,
};
