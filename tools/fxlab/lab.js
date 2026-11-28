// Runs inside headless Chromium: builds the mock scene, draws frames, makes contact sheets.
import * as fx from '/lab/fx.js';

for (const [k, v] of Object.entries(fx.API)) globalThis[k] = v;

const S = { effect: null, scene: null, opts: null, canvas: null, fxCanvas: null, pool: null };

async function setup(opts) {
  S.opts = opts;
  const mod = await import(opts.effectURL);
  if (typeof mod.draw !== 'function') throw new Error('the effect file must export function draw(f, ctx)');
  const kind = mod.kind || (opts.flight ? 'flight' : 'close');
  const duration = mod.duration ?? 0.8;
  const theme = fx.themeFromSpec(opts.theme);
  S.effect = mod;
  S.scene = kind === 'flight'
    ? fx.flightScene({ theme, layout: opts.layout, seed: opts.seed, duration, speed: opts.speed })
    : fx.closeScene({ theme, padSize: new fx.CGSize(opts.padW, opts.padH), floating: opts.floating, seed: opts.seed, duration, speed: opts.speed });
  const { width, height } = S.scene.size, k = opts.scale;
  S.canvas = new OffscreenCanvas(Math.round(width * k), Math.round(height * k));
  // A document canvas (not OffscreenCanvas), so SVG filters (brightness, colorMultiply) can be referenced.
  S.fxCanvas = fx.makeCanvas(Math.round(width * k), Math.round(height * k));
  S.pool = new fx.LayerPool(S.canvas.width, S.canvas.height);
  await document.fonts.ready;
  const r = (x) => x && { x: x.x, y: x.y, width: x.width, height: x.height };
  return { kind, duration, scaledDuration: S.scene.frame(0).duration, size: S.scene.size,
    pad: r(S.scene.pad), sink: r(S.scene.sink), from: r(S.scene.from), to: r(S.scene.to), notch: r(S.scene.notch),
    focus: r(S.scene.focus), cells: S.scene.kind === 'close' ? [S.scene.frame(0).cells.cols, S.scene.frame(0).cells.rows, S.scene.frame(0).cells.size] : null };
}

/** Draws frame t: the effect on its own transparent layer (like the real Canvas window), over the backdrop. */
function drawFrame(t) {
  const k = S.opts.scale;
  const fg = S.fxCanvas.getContext('2d', { willReadFrequently: true });
  fg.setTransform(1, 0, 0, 1, 0, 0); fg.globalAlpha = 1; fg.globalCompositeOperation = 'source-over'; fg.filter = 'none';
  fg.clearRect(0, 0, S.fxCanvas.width, S.fxCanvas.height);
  const f = S.scene.frame(t);
  const ctx = new fx.Ctx(fg, S.pool, fx.CGAffineTransform.scale(k, k));
  fx.resetStats();
  const t0 = performance.now();
  let error = null;
  if (S.scene.kind === 'flight' && !S.opts.noNotch) { fx.drawFlightNotch(ctx, f); fx.resetStats(); }
  try {
    if (S.scene.kind === 'flight') {
      // Like FlightEffectCanvas: the effect only runs for 0 < t < 1; the ends show the real pad pictures.
      if (f.t <= 0) f.drawFrom(ctx); else if (f.t >= 1) f.drawTo(ctx); else S.effect.draw(f, ctx);
    } else if (f.t < 1) {
      // Like CloseEffectCanvas: nothing is drawn once t reaches 1.
      S.effect.draw(f, ctx);
    }
  } catch (e) { error = String(e && e.stack || e); }
  fg.getImageData(0, 0, 1, 1); // make the canvas finish its drawing, so the time is honest
  const ms = performance.now() - t0;
  const g = S.canvas.getContext('2d');
  g.setTransform(1, 0, 0, 1, 0, 0); g.globalCompositeOperation = 'source-over'; g.globalAlpha = 1;
  g.clearRect(0, 0, S.canvas.width, S.canvas.height);
  fx.drawBackdrop(g, S.opts.backdrop, S.canvas.width, S.canvas.height);
  g.drawImage(S.fxCanvas, 0, 0);
  return { t, ms, stats: fx.getStats(), error };
}

async function toPNG(canvas) {
  const blob = await canvas.convertToBlob({ type: 'image/png' });
  const buf = new Uint8Array(await blob.arrayBuffer());
  let s = ''; for (let i = 0; i < buf.length; i += 0x8000) s += String.fromCharCode.apply(null, buf.subarray(i, i + 0x8000));
  return btoa(s);
}

function cropRect(crop) {
  const k = S.opts.scale, W = S.canvas.width, H = S.canvas.height;
  if (!crop) return [0, 0, W, H];
  const x0 = Math.max(0, Math.floor((crop.x) * k)), y0 = Math.max(0, Math.floor((crop.y) * k));
  const x1 = Math.min(W, Math.ceil((crop.x + crop.width) * k)), y1 = Math.min(H, Math.ceil((crop.y + crop.height) * k));
  return [x0, y0, x1 - x0, y1 - y0];
}

async function frame(t, crop) {
  const info = drawFrame(t);
  const [x, y, w, h] = cropRect(crop);
  const c = new OffscreenCanvas(w, h);
  c.getContext('2d').drawImage(S.canvas, x, y, w, h, 0, 0, w, h);
  return { ...info, png: await toPNG(c) };
}

// Contact sheet: frames in a grid, each labelled with t (and optionally a Swift reference frame underneath).
const sheet = { canvas: null, cols: 0, cw: 0, ch: 0, n: 0, label: 0 };
function sheetBegin(n, cols, cellW, crop, title, pairs) {
  const [, , w, h] = cropRect(crop);
  const cw = Math.round(cellW), ch = Math.round(cellW * h / w);
  const label = 22, pad = 6, head = 30;
  const rows = Math.ceil(n / cols);
  const cellH = (pairs ? 2 * ch + 4 : ch) + label;
  sheet.canvas = new OffscreenCanvas(cols * (cw + pad) + pad, head + rows * (cellH + pad) + pad);
  Object.assign(sheet, { cols, cw, ch, cellH, pad, head, label, crop, pairs });
  const g = sheet.canvas.getContext('2d');
  g.fillStyle = '#111'; g.fillRect(0, 0, sheet.canvas.width, sheet.canvas.height);
  g.fillStyle = '#ddd'; g.font = '600 16px "DejaVu Sans", sans-serif'; g.textBaseline = 'middle';
  g.fillText(title, pad, head / 2);
}
async function sheetAdd(i, t, refDataURL) {
  const info = drawFrame(t);
  const [x, y, w, h] = cropRect(sheet.crop);
  const g = sheet.canvas.getContext('2d');
  const col = i % sheet.cols, row = Math.floor(i / sheet.cols);
  const X = sheet.pad + col * (sheet.cw + sheet.pad), Y = sheet.head + row * (sheet.cellH + sheet.pad);
  g.imageSmoothingEnabled = true; g.imageSmoothingQuality = 'high';
  g.drawImage(S.canvas, x, y, w, h, X, Y + sheet.label, sheet.cw, sheet.ch);
  if (refDataURL) {
    const img = await createImageBitmap(await (await fetch(refDataURL)).blob());
    const k = img.width / S.scene.size.width; // reference frames may be 1x or 2x
    const [rx, ry, rw, rh] = cropRect(sheet.crop).map((v) => v / S.opts.scale * k);
    g.drawImage(img, rx, ry, rw, rh, X, Y + sheet.label + sheet.ch + 4, sheet.cw, sheet.ch);
  }
  g.fillStyle = info.error ? '#f66' : '#fff'; g.font = '600 15px "DejaVu Sans Mono", monospace'; g.textBaseline = 'middle';
  g.fillText(`t=${t.toFixed(3)}${info.error ? '  ERROR' : ''}`, X + 2, Y + sheet.label / 2);
  if (sheet.pairs) {
    g.font = '11px "DejaVu Sans", sans-serif'; g.fillStyle = '#9cf';
    g.fillText('js', X + sheet.cw - 18, Y + sheet.label / 2);
  }
  return info;
}
async function sheetEnd() { return toPNG(sheet.canvas); }

window.fxlab = { setup, frame, sheetBegin, sheetAdd, sheetEnd, ready: true };
