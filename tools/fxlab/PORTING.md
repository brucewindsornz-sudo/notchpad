# fxlab: prototype NotchPad animations in JavaScript, then port them to Swift

fxlab draws a closing or boomerang animation in seconds, here in the Linux sandbox, with an API that mirrors
the Swift one almost line for line. Design the animation here until it looks excellent, then port it to Swift
by following the table below literally. Same structure, same helper names, same numbers: same picture.

## Run it

Nothing to install: use the team's shared copy in the fx-lab worktree (it always has the latest fixes).

    FX=/home/user/workspace/wt/lab/tools/fxlab
    node $FX/render.js $FX/effects/sample-close.js --frames 24 --crop --sheet /tmp/me/sheet.png
    node $FX/render.js my-effect.js --t 0.37 --scale 2 --out /tmp/me/frame.png
    node $FX/render.js my-effect.js --video /tmp/me/effect.mp4 --fps 60
    node $FX/render.js $FX/effects/sample-flight.js --layout far --frames 24 --sheet /tmp/me/sheet.png
    node $FX/render.js --help

If you want your own install instead (for example in a worktree of your own after merging fx-lab):
`npm install --prefix tools/fxlab` (one small package, playwright-core; it uses the Chromium already in
`~/.cache/ms-playwright`). Without a local install, render.js falls back to the shared one above.

Useful options: `--theme stargate` (any id from `--list-themes`), `--floating` (close effects: the floating
card instead of the docked pad), `--layout near|far|left|right|below` (flights), `--backdrop dark|light|photo`
(animations play over the user's real desktop: check them on all three), `--crop [margin]` (sheet shows the
pad area only, so it stays readable when shrunk), `--cols N`, `--t-range 0.2:0.6` (zoom into part of the run),
`--seed N`, `--speed 1.5`, `--compare DIR/name` (pairs each frame with a Mac frame `DIR/name-NNN.png`).

Every run prints the cost of each frame and a summary:

    cost: 24 frames, average 7.3 ms, worst 13.2 ms at t=0.333; draw calls per frame: average 77, most 163; most blurred draws 1

Draw calls are fill + stroke + pad pictures + text. The time is Chromium's software renderer on a busy
2-CPU sandbox, so treat it as a relative number: if one frame costs 10 times another, the Mac will feel it too.

## The effect file

An ES module. Every API name below is a global, exactly as Swift's helpers are visible to every file in the
module, so no import line is needed (you may `import { ... } from 'fxlab'` if you prefer).

    export const kind = 'close';        // or 'flight'
    export const duration = 0.9;        // seconds at normal speed: Swift's `let duration: Double = 0.9`
    export function draw(f, ctx) { ... }  // Swift: func draw(_ f: CloseFrame, _ ctx: GraphicsContext)

Like Swift, `draw` must depend only on `f`: no state kept between frames, no clock, no `Math.random()`.
Use `f.seed` with `CloseRNG` or `closeHash`.

The harness behaves like the app around your `draw`: a close effect is not called at t = 1 (nothing is shown);
a flight effect is called only for 0 < t < 1 (t = 0 shows `drawFrom`, t = 1 shows `drawTo`), and a black
notch fades in under it for flights (`--no-notch` hides it), as FlightEffectCanvas does. Your effect draws on
its own transparent layer, which is then laid over the backdrop: exactly like the app's see-through window,
so `plusLighter` adds light to your own drawing, not to the desktop, and `destinationOut` cannot cut holes in
the desktop.

## Fidelity

Checked against 16 frames of the Stargate placeholder rendered by the real app on a Mac (theme notch, docked,
pad 500 × 290, canvas 820 × 450, seed 20261128, t = i/15): `effects/sample-close.js` gives the same pad
rectangle, the same glow line (pixel values within 1 to 3 of 255 down its blurred profile) and the same sparks
(every spark pixel in the Mac frames below the pad is in the fxlab frames at the same place; the few extra
Mac pixels are anti-aliasing). `node tools/fxlab/selftest.js` checks closeHash, CloseRNG and closeNoise against
values computed independently with explicit mod 2^32 arithmetic: bit-identical.

Known differences: the pad picture's text uses Linux fonts (Liberation Sans / DejaVu) instead of SF, so text
is a little wider; signature themes' own fonts (Futura, Menlo, Baskerville...) are approximated by their
fallback design. Cell colours are an area average close to, not exactly, CoreGraphics' downscale, so a cell
right on the pad's curved edge can differ slightly in alpha.

## Porting table

JS on the left, Swift on the right. Swift lines are what you type, including labels.

### Numbers and helpers

| JS | Swift |
|---|---|
| `clamp01(x)`, `lerp(a, b, t)`, `phase(t, a, b)` | `clamp01(x)`, `lerp(a, b, t)`, `phase(t, a, b)` |
| `easeIn(t)`, `easeOut(t)`, `easeInOut(t)`, `smoothstep(a, b, x)` | same names, same arguments |
| `closeHash(i, j, f.seed)` | `closeHash(i, j, f.seed)` |
| `closeHash(i, j, (f.seed + 7) >>> 0)` | `closeHash(i, j, f.seed &+ 7)` (seed is UInt32: use `&+`, `&*`, and `>>> 0` in JS) |
| `closeHash(i, j, (f.seed ^ 0x51ED) >>> 0)` | `closeHash(i, j, f.seed ^ 0x51ED)` |
| `closeNoise(x, y, f.seed)` | `closeNoise(x, y, f.seed)` |
| `const rng = new CloseRNG(f.seed)` | `var rng = CloseRNG(f.seed)` |
| `rng.next()`, `rng.range(a, b)`, `rng.int(n)` | `rng.next()`, `rng.range(a, b)`, `rng.int(n)` |
| `const r2 = rng.copy()` | `var r2 = rng` (a struct: a copy) |
| `Math.sin(x)`, `Math.cos`, `Math.atan2(y, x)`, `Math.sqrt(x)`, `Math.pow(a, b)`, `Math.hypot(a, b)`, `Math.exp`, `Math.abs` | `sin(x)`, `cos`, `atan2(y, x)`, `sqrt(x)`, `pow(a, b)`, `hypot(a, b)`, `exp`, `abs` |
| `Math.min(a, b)`, `Math.max(a, b)` | `min(a, b)`, `max(a, b)` (both arguments the same type) |
| `Math.PI` | `Double.pi` |
| `Math.floor(x)` | `x.rounded(.down)` (a Double); `Int(x.rounded(.down))` for an Int |
| `Math.trunc(x)` (to an integer) | `Int(x)` (truncates towards zero; crashes if x is NaN or huge) |
| `Math.round(x)` | `x.rounded()` (both round halves away from zero; JS rounds -2.5 to -2, Swift to -3) |
| `x % y` for fractional numbers | `x.truncatingRemainder(dividingBy: y)` (Swift `%` is for Int only) |
| `Math.floor(a / b)` for integers | `a / b` only if both are ≥ 0 (Swift Int division truncates towards zero) |
| `for (let i = 0; i < n; i++)` | `for i in 0..<n` (crashes if n < 0: guard it, or use `while`) |
| `for (let i = 0; i < n; i += 5)` | `for i in stride(from: 0, to: n, by: 5)` |
| `const x = ...` / `let x = ...` | `let x: Double = ...` / `var x: Double = ...` (give the type: see "Type checker") |

### Colours

| JS | Swift |
|---|---|
| `new RGBA(r, g, b)`, `new RGBA(r, g, b, a)` | `RGBA(r, g, b)`, `RGBA(r, g, b, a)` |
| `RGBA.white`, `RGBA.black`, `RGBA.clear` | `RGBA.white`, `RGBA.black`, `RGBA.clear` |
| `c.mix(o, t)`, `c.alpha(a)`, `c.r`, `c.a` | `c.mix(o, t)`, `c.alpha(a)`, `c.r`, `c.a` |
| `f.bg`, `f.text`, `f.accent`, `f.dark` | `f.bg`, `f.text`, `f.accent`, `f.dark` |

Where Swift needs a SwiftUI `Color` (shadings, gradients, text), write `c.color`. In JS pass the RGBA itself
(JS also accepts `c.color`, which is the same object, so you can keep the Swift spelling).

### Geometry

| JS | Swift |
|---|---|
| `new CGPoint(x, y)`, `CGPoint.zero` | `CGPoint(x: x, y: y)`, `.zero` |
| `new CGSize(w, h)` | `CGSize(width: w, height: h)` |
| `new CGRect(x, y, w, h)` | `CGRect(x: x, y: y, width: w, height: h)` |
| `new CGRect(origin, size)` | `CGRect(origin: origin, size: size)` |
| `r.minX r.midX r.maxX r.minY r.midY r.maxY r.width r.height r.origin r.size` | same (CGFloat: wrap in `Double(...)` to mix with Double) |
| `r.insetBy(dx, dy)`, `r.offsetBy(dx, dy)` | `r.insetBy(dx: dx, dy: dy)`, `r.offsetBy(dx: dx, dy: dy)` |
| `r.contains(p)`, `r.union(o)`, `r.intersects(o)`, `r.intersection(o)` | `r.contains(p)`, `r.union(o)`, `r.intersects(o)`, `r.intersection(o)` |
| `CGAffineTransform.translation(x, y)` | `CGAffineTransform(translationX: x, y: y)` |
| `CGAffineTransform.scale(x, y)` | `CGAffineTransform(scaleX: x, y: y)` |
| `CGAffineTransform.rotation(a)` | `CGAffineTransform(rotationAngle: a)` |
| `m.translatedBy(x, y)`, `m.scaledBy(x, y)`, `m.rotated(a)` | `m.translatedBy(x: x, y: y)`, `m.scaledBy(x: x, y: y)`, `m.rotated(by: a)` |
| `m.concatenating(n)`, `m.inverted()`, `p.applying(m)` | same |

### Paths (SwiftUI.Path)

| JS | Swift |
|---|---|
| `const p = new Path()` | `var p = Path()` |
| `new Path((p) => { p.move(a); p.addLine(b) })` | `Path { p in p.move(to: a); p.addLine(to: b) }` |
| `Path.rect(r)` | `Path(r)` |
| `Path.ellipse(r)` | `Path(ellipseIn: r)` |
| `Path.roundedRect(r, k)` | `Path(roundedRect: r, cornerRadius: k, style: .continuous)` |
| `Path.roundedRect(r, k, 'circular')` | `Path(roundedRect: r, cornerRadius: k, style: .circular)` |
| `p.move(pt)` | `p.move(to: pt)` |
| `p.addLine(pt)` | `p.addLine(to: pt)` |
| `p.addLines([a, b, c])` | `p.addLines([a, b, c])` |
| `p.addQuadCurve(to, control)` | `p.addQuadCurve(to: to, control: control)` |
| `p.addCurve(to, c1, c2)` | `p.addCurve(to: to, control1: c1, control2: c2)` |
| `p.addArc(c, r, a0, a1, cw)` (radians) | `p.addArc(center: c, radius: r, startAngle: .radians(a0), endAngle: .radians(a1), clockwise: cw)` |
| `p.addRect(r)`, `p.addRects([r1, r2])` | `p.addRect(r)`, `p.addRects([r1, r2])` |
| `p.addEllipse(r)` | `p.addEllipse(in: r)` |
| `p.addRoundedRect(r, k)` | `p.addRoundedRect(in: r, cornerSize: CGSize(width: k, height: k), style: .continuous)` |
| `p.addPath(q)`, `p.addPath(q, m)` | `p.addPath(q)`, `p.addPath(q, transform: m)` |
| `p.closeSubpath()` | `p.closeSubpath()` |
| `p.applying(m)`, `p.offsetBy(dx, dy)` | `p.applying(m)`, `p.offsetBy(dx: dx, dy: dy)` |
| `p.boundingRect`, `p.isEmpty`, `p.currentPoint` | same (`currentPoint` is optional in Swift) |
| `p.contains(pt)` | `p.contains(pt)` |
| `p.trimmedPath(a, b)` | `p.trimmedPath(from: a, to: b)` |
| `const q = p.copy()` | `var q = p` (Path is a value) |
| `closePadPath(r, floating)` | `closePadPath(in: r, floating: floating)` |

Always write `style: .continuous` or `.circular` explicitly in Swift, so the two sides cannot disagree.
The continuous ("squircle") corner here is the usual published approximation of Apple's curve: very close,
not pixel-exact.

**Arc direction trap.** SwiftUI's `clockwise:` is measured as if y pointed up, so in the canvas (y down)
`clockwise: true` turns the way that looks counter-clockwise on screen. Canvas 2D's own flag is called
`counterclockwise` and means what it looks like. They are the same flag: fxlab's `addArc(..., cw)` passes
your value straight through, so **copy the boolean unchanged** between JS and Swift. What you see in fxlab is
what Swift draws. Example: `p.addArc(c, 50, 0, Math.PI / 2, false)` draws a quarter circle from the right
point down to the bottom point (looks clockwise on screen); with `true` it goes the long way round (three
quarters, looking counter-clockwise).

**Holes.** For a ring or any shape with a hole made of two subpaths, fill with `{ eoFill: true }`
(Swift `style: FillStyle(eoFill: true)`); do not rely on the winding direction of ellipses.

### Drawing (GraphicsContext)

| JS | Swift |
|---|---|
| `const g = ctx.copy()` | `var g = ctx` |
| `g.opacity = 0.5`, `g.opacity = g.opacity * k` | `g.opacity = 0.5`, `g.opacity = g.opacity * k` |
| `g.blendMode = 'plusLighter'` | `g.blendMode = .plusLighter` |
| `g.translateBy(x, y)`, `g.scaleBy(x, y)` | `g.translateBy(x: x, y: y)`, `g.scaleBy(x: x, y: y)` |
| `g.rotate(a)` (radians) | `g.rotate(by: .radians(a))` |
| `g.concatenate(m)` | `g.concatenate(m)` |
| `g.clip(path)` | `g.clip(to: path)` |
| `g.clip(path, { eoFill: true })` | `g.clip(to: path, style: FillStyle(eoFill: true))` |
| `g.clip(path, { inverse: true })` | `g.clip(to: path, options: .inverse)` |
| `g.clipToLayer((layer) => { ... })` | `g.clipToLayer { layer in ... }` |
| `g.clipToLayer((layer) => { ... }, { opacity: 0.5 })` | `g.clipToLayer(opacity: 0.5) { layer in ... }` |
| `ctx.drawLayer((layer) => { ... })` | `ctx.drawLayer { layer in ... }` |
| `ctx.fill(path, shading)` | `ctx.fill(path, with: shading)` |
| `ctx.fill(path, shading, { eoFill: true })` | `ctx.fill(path, with: shading, style: FillStyle(eoFill: true))` |
| `ctx.stroke(path, shading, 2)` | `ctx.stroke(path, with: shading, lineWidth: 2)` |
| `ctx.stroke(path, shading, { lineWidth: 2, lineCap: 'round', lineJoin: 'round' })` | `ctx.stroke(path, with: shading, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))` |
| `... { lineWidth: 2, dash: [6, 4], dashPhase: 3 }` | `StrokeStyle(lineWidth: 2, dash: [6, 4], dashPhase: 3)` (arguments in this order: lineWidth, lineCap, lineJoin, miterLimit, dash, dashPhase) |

`lineCap`: `'butt' | 'round' | 'square'` = `.butt .round .square`; `lineJoin`: `'miter' | 'round' | 'bevel'`.

Blend modes (JS string = Swift case): `normal multiply screen overlay darken lighten colorDodge colorBurn
softLight hardLight difference exclusion hue saturation color luminosity plusLighter sourceAtop sourceIn
sourceOut destinationOver destinationIn destinationOut destinationAtop xor copy clear`. `plusDarker` exists
in Swift but has no canvas equivalent: not available in fxlab, do not use it.

In a `drawLayer` closure, the layer starts with opacity 1, normal blend and no filters, and keeps the outer
transform; when the closure ends, the whole layer is composited with the outer context's opacity, blend mode,
filters and clip. (That the inner context starts with fresh opacity/blend/filters is how fxlab models
SwiftUI; it is not yet checked on the Mac. To be safe in Swift, set what you rely on inside the closure.) In Swift the closure's `layer` is `inout`, so `layer.blendMode = .destinationOut`
inside it works the same as in JS.

### Shading and gradients

| JS | Swift |
|---|---|
| `Shading.color(c)` | `.color(c.color)` |
| `Gradient.colors([a, b])` | `Gradient(colors: [a.color, b.color])` |
| `Gradient.stops([[a, 0], [b, 0.7], [c, 1]])` | `Gradient(stops: [.init(color: a.color, location: 0), .init(color: b.color, location: 0.7), .init(color: c.color, location: 1)])` |
| `Shading.linearGradient(g, p0, p1)` | `.linearGradient(g, startPoint: p0, endPoint: p1)` |
| `Shading.radialGradient(g, c, r0, r1)` | `.radialGradient(g, center: c, startRadius: r0, endRadius: r1)` |
| `Shading.conicGradient(g, c, a)` (radians) | `.conicGradient(g, center: c, angle: .radians(a))` |

Gradient points are in the context's current coordinates (after translate/scale/rotate), on both sides.
Conic gradients start at angle `a` (0 = pointing right) and sweep clockwise on screen in fxlab; that SwiftUI
sweeps the same way is **not yet checked on the Mac**: check one Trial frame before relying on it.

### Filters

`g.addFilter(F)` (Swift `g.addFilter(F)`) applies to everything drawn later with `g`, in the order added.

| JS | Swift |
|---|---|
| `Filter.blur(r)` | `.blur(radius: r)` |
| `Filter.shadow(c, r)`, `Filter.shadow(c, r, x, y)` | `.shadow(color: c.color, radius: r)`, `.shadow(color: c.color, radius: r, x: x, y: y)` |
| `Filter.brightness(x)` | `.brightness(x)` (adds x to every channel: Apple's docs) |
| `Filter.contrast(x)`, `Filter.saturation(x)`, `Filter.grayscale(x)` | `.contrast(x)`, `.saturation(x)`, `.grayscale(x)` |
| `Filter.hueRotation(a)` (radians) | `.hueRotation(.radians(a))` |
| `Filter.colorInvert(1)` / `Filter.colorInvert(x)` | `.colorInvert(1)` / `.colorInvert(x)` (write the amount: the Swift default is not checked) |
| `Filter.colorMultiply(c)` | `.colorMultiply(c.color)` |
| `Filter.shadow(c, r, x, y, { shadowOnly: true })` | `.shadow(color: c.color, radius: r, x: x, y: y, options: .shadowOnly)` (draws only the shadow) |
| `Filter.alphaThreshold(lo, hi, c)` | `.alphaThreshold(min: lo, max: hi, color: c.color)` (alpha within lo…hi becomes `c`, anything else clear; write all three: Swift's defaults are `max: 1`, `color: .black`) |
| `Filter.colorMatrix([r1,r2,r3,r4,r5, g1,…,g5, b1,…,b5, a1,…,a5])` | `var m = ColorMatrix(); m.r1 = …; …` then `.colorMatrix(m)` (20 numbers, row by row; the 5th of each row is an offset; the fields are `Float`, so write `Float(x)` for a `Double`) |

**Blur radius.** Checked on the Mac frames: SwiftUI's `blur(radius: 6)` profile matches CSS `blur(6px)`
(the radius is the Gaussian's standard deviation) to within 1 to 3 levels out of 255. Shadow radius uses the
same rule (shadow is not yet checked on the Mac). Filter sizes scale with the context's transform in fxlab;
that SwiftUI does the same under `scaleBy` is not yet checked: avoid blurring inside a scaled context, or check
a Trial frame.

Metaballs and goo: draw blurred blobs inside a `drawLayer` on a context that has
`Filter.alphaThreshold(0.5, 1, colour)`; the blobs merge where their blurred edges overlap.

Not available in fxlab (exist in SwiftUI): `luminanceToAlpha`, `alphaMultiply`, shader filters (macOS 14+
anyway), `projectionTransform`, shadow options other than `.shadowOnly`, and the `blendMode:` argument of
`.shadow`. Ask `/root/fxlab_builder` if you need one.

### Text

| JS | Swift |
|---|---|
| `const t = ctx.resolveText('ﾊ', { size: 12, weight: 'bold', design: 'monospaced', color: c })` | `let t = ctx.resolve(Text("ﾊ").font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundColor(c.color))` |
| `ctx.drawText(t, p)` / `ctx.drawText(t, p, 'center')` | `ctx.draw(t, at: p)` / `ctx.draw(t, at: p, anchor: .center)` |
| `ctx.drawText(t, p, 'topLeading')` | `ctx.draw(t, at: p, anchor: .topLeading)` |

Weights: `ultraLight thin light regular medium semibold bold heavy black`. Designs: `default monospaced
rounded serif`. Anchors: `topLeading top topTrailing leading center trailing bottomLeading bottom
bottomTrailing`, or `{ x, y }` = `UnitPoint(x: x, y: y)`. The anchor is placed on the text's line box (font
ascent + descent), as SwiftUI does. Fonts differ (Linux has no SF), so allow for glyphs about 5% wider or
narrower. Resolve each distinct glyph once per frame and reuse it: resolving is the slow part in Swift.

### The frame (close effects: CloseFrame)

| JS | Swift |
|---|---|
| `f.t`, `f.duration`, `f.seconds` | `f.t`, `f.duration`, `f.seconds` |
| `f.size`, `f.pad`, `f.sink`, `f.target`, `f.floating`, `f.seed` | same |
| `f.cells.cols`, `f.cells.rows`, `f.cells.size` | same |
| `f.cells.color(col, row)`, `f.cells.rect(col, row)` | `f.cells.color(col, row)`, `f.cells.rect(col, row)` |
| `f.padPath` | `f.padPath` |
| `f.padPathIn(r)` | `f.padPath(in: r)` |
| `f.drawPad(ctx)` | `f.drawPad(ctx)` |
| `f.drawPad(ctx, r)` | `f.drawPad(ctx, in: r)` |
| `f.drawPad(ctx, null, 0.5)` | `f.drawPad(ctx, opacity: 0.5)` |
| `f.drawPad(ctx, r, 0.5)` | `f.drawPad(ctx, in: r, opacity: 0.5)` |

To draw part of the pad (a slice, a shard, a strip), do it the Swift way: copy the context, clip to the piece,
move it, then draw the whole pad picture through the clip:

    const g = ctx.copy();                       // var g = ctx
    g.translateBy(dx, dy);                      // g.translateBy(x: dx, y: dy)
    g.clip(Path.rect(piece));                   // g.clip(to: Path(piece))
    f.drawPad(g);                               // f.drawPad(g)

Mock scene (matches `CloseScene.mock` with pad 500 × 290, as the Mac build frames): docked canvas
820 × 450, pad (160, 0, 500, 290), sink (320, 0, 180, 32); floating canvas 820 × 610, pad (160, 160, 500, 290),
sink (390, 302, 40, 6). Cells: side `max(6, sqrt(w × h / 5000))` = 6 pt, 84 × 49. Seed 20261128.

### The frame (boomerang effects: FlightFrame)

| JS | Swift |
|---|---|
| `f.t`, `f.duration`, `f.seconds`, `f.size`, `f.seed` | same |
| `f.from` (the floating card), `f.to` (the docked pad), `f.notch` | same |
| `f.distance` (centre to centre, points) | `f.distance` |
| `f.fromCells`, `f.toCells` | same |
| `f.fromPath`, `f.toPath` | same |
| `f.fromPathIn(r)`, `f.toPathIn(r)` | `f.fromPath(in: r)`, `f.toPath(in: r)` |
| `f.drawFrom(ctx, r, op)`, `f.drawTo(ctx, r, op)` | `f.drawFrom(ctx, in: r, opacity: op)`, `f.drawTo(ctx, in: r, opacity: op)` |

Mock scene (matches `FlightScene.mock`): canvas 1180 × 760, `to` (340, 0, 500, 290), `notch` (500, 0, 180, 32),
`from` origin by layout: near (455, 172), far (625, 440), left (55, 268), right (625, 268), below (340, 440).
Duration is scaled by distance as in the app: `duration × lerp(0.65, 1.2, smoothstep(24, 1100, distance))`.

## Scoping state: `ctx.copy()` is `var g = ctx`

There is no save/restore on either side. A copy has its own opacity, blend mode, clip, filters and transform;
changing the copy never changes `ctx`. Make a copy for every group of drawing that needs its own state, and
make it as late as possible. Never change `ctx` itself unless you mean it for everything after (in Swift
`ctx` is a `let` parameter, so you could not anyway: always copy first).

## Performance

- Blur is the expensive thing, on the Mac too. Never blur the whole canvas, and never blur hundreds or
  thousands of separate items. Draw the items that should glow into one `drawLayer` and blur that one layer,
  or draw a few big soft shapes. The run summary prints "most blurred draws": keep it in single figures.
- Keep draw calls per frame in the low thousands at most (a few hundred is comfortable). Merge many small
  rectangles of one colour into one Path (`p.addRect` many times, then one fill) where you can.
- Resolve text once per distinct glyph and size, not once per draw.
- Fewer, bigger layers beat many small ones; `clipToLayer` and `drawLayer` each cost a full-canvas layer here.
- Respect `testNoEffects` in Swift (no blur, no shadow on the build machine without a graphics card): put
  filters behind `if !testNoEffects { g.addFilter(...) }` so the effect still reads without them.

## Swift type-checker rules (from TEAM.md; they save a 5-minute build)

- Keep expressions short and give locals explicit types: `let x: Double = Double(cell.midX) + cos(angle) * speed`.
- Never mix `CGFloat` and `Double` in one expression: convert explicitly (`Double(r.minX)`, `CGFloat(x)`).
  CGRect/CGPoint members are CGFloat; RGBA members, `f.t`, helpers and RNG results are Double.
- Split long sums into several `let` lines, as the sample does.
- macOS 13 is the minimum: no newer APIs without `#available` and a good fallback. Not usable: Path boolean
  operations (`union`, `intersection`, `subtracting`, ... are macOS 14), `RectangleCornerRadii`, shader
  filters (`colorShader`, `layerShader`, `distortionShader`: macOS 14).
- `GraphicsContext` is a value: `var g = ctx` copies it. There is no save/restore.

## Worked example: the Stargate placeholder in both languages

JS (`effects/sample-close.js`):

```js
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
```

Swift (`Sources/CloseStargate.swift`, the code the Mac frames came from):

```swift
struct StargateClose: CloseEffectRenderer {
    let duration: Double = 0.8

    func draw(_ f: CloseFrame, _ ctx: GraphicsContext) {
        let lift: Double = easeIn(phase(f.t, 0.0, 0.8))               // stage 1: 0 → 0.8 of the run
        // The pad, squeezed towards the sink.
        let r = CGRect(x: lerp(f.pad.minX, f.sink.minX, lift), y: lerp(f.pad.minY, f.sink.minY, lift),
                       width: lerp(f.pad.width, f.sink.width, lift), height: lerp(f.pad.height, f.sink.height, lift))
        f.drawPad(ctx, in: r, opacity: 1 - phase(f.t, 0.6, 0.8))
        // A glow line along the bottom edge.
        let glow: Double = sin(Double.pi * phase(f.t, 0.0, 0.8))
        var g = ctx                                                    // a copy = ctx.save() … ctx.restore()
        g.blendMode = .plusLighter
        g.addFilter(.blur(radius: 6))
        g.fill(Path(CGRect(x: r.minX, y: r.maxY - 3, width: r.width, height: 6)), with: .color(f.accent.alpha(0.8 * glow).color))
        // Sparks: every 5th cell of the pad picture flies off, in its own colour.
        var rng = CloseRNG(f.seed)
        var row = 0
        while row < f.cells.rows {
            var col = 0
            while col < f.cells.cols {
                let angle: Double = rng.range(0, Double.pi * 2)
                let speed: Double = rng.range(40, 160)
                let start: Double = rng.range(0, 0.4)
                let c: RGBA = f.cells.color(col, row)
                col += 5
                if c.a <= 0 { continue }
                let life: Double = phase(f.t, start, start + 0.5)
                if life <= 0 || life >= 1 { continue }
                let cell: CGRect = f.cells.rect(col - 5, row)
                let x: Double = Double(cell.midX) + cos(angle) * speed * easeOut(life)
                let y: Double = Double(cell.midY) + sin(angle) * speed * easeOut(life) + 60 * life * life
                ctx.fill(Path(CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3)),
                         with: .color(c.mix(f.accent, life).alpha(1 - life).color))
            }
            row += 5
        }
    }
}
```

Note how the random numbers are drawn in the same order on both sides, including for cells that are then
skipped: change the order and every spark moves.

The boomerang sample (`effects/sample-flight.js`) is a port of `drawSampleFlight` in
`Sources/FlightEffects.swift` (branch fx-flight), the glide the placeholder flights use.

## Files

- `fx.js`: the mirror API (runs in the page; helpers also load in Node for tests).
- `lab.js`, `page.html`: the harness page (scene, frame drawing, contact sheets).
- `render.js`: the command line; drives headless Chromium and ffmpeg. Browsers always exit, even on errors.
- `themes.json`: built-in themes, made from `Sources/Themes.swift` by `node tools/fxlab/sync-themes.js`.
- `selftest.js`: hash and random-number check.
- `effects/`: sample effects.
