#!/usr/bin/env node
// fxlab renderer: draws an effect file with headless Chromium and writes frames, contact sheets or a video.
// Run `node tools/fxlab/render.js --help` for the options.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const HELP = `usage: node tools/fxlab/render.js EFFECT.js [options]

What to make (one or more):
  --t 0.37 --out frame.png      one frame
  --frames 24 --sheet sheet.png contact sheet of 24 frames, t = i/(n-1)
  --frames 16 --out-dir DIR     frames as DIR/<name>-000.png ... (same naming as the Mac build)
  --video out.mp4 [--fps 60]    a video at real speed (ffmpeg)
  --compare DIR/stargate        sheet pairing each frame with the Mac's DIR/stargate-NNN.png (use with --frames, --sheet)

Scene:
  --theme ID                    theme id from Themes.swift (default notch); --list-themes shows them
  --floating                    close: the floating pad (a rounded card) instead of the docked one
  --layout near|far|left|right|below   flight: where the floating pad starts (default far)
  --pad 500x290                 close: pad size (default 500x290, as the Mac build frames)
  --seed N                      default 20261128
  --speed K                     duration multiplier (the app's speed setting), default 1
  --backdrop dark|light|photo|none   what is behind the canvas (default dark, as the Mac build frames)

Output:
  --scale K                     pixels per point (default 1; 2 = Retina)
  --cols N                      sheet columns (default 4 with --crop, else 3); sheet is about 1500 px wide
  --width PX                    sheet width (default 1500)
  --crop [MARGIN]               sheet/frames show only the pad area (close: pad; flight: from ∪ to) plus MARGIN points (default 60)
  --t-range A:B                 frames span t from A to B instead of 0:1
  --quiet                       no per-frame lines
  --no-notch                    flight: leave out the black notch the app draws under the effect
`;

function parseArgs(argv) {
  const o = { theme: 'notch', layout: 'far', seed: 20261128, speed: 1, backdrop: 'dark', scale: 1, fps: 60, width: 1500,
    padW: 500, padH: 290, floating: false };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i], next = () => { if (i + 1 >= argv.length) die(`${a} needs a value`); return argv[++i]; };
    switch (a) {
      case '-h': case '--help': console.log(HELP); process.exit(0);
      case '--t': o.t = Number(next()); break;
      case '--out': o.out = next(); break;
      case '--frames': o.frames = parseInt(next(), 10); break;
      case '--sheet': o.sheet = next(); break;
      case '--out-dir': o.outDir = next(); break;
      case '--video': o.video = next(); break;
      case '--fps': o.fps = Number(next()); break;
      case '--compare': o.compare = next(); break;
      case '--theme': o.theme = next(); break;
      case '--floating': o.floating = true; break;
      case '--layout': o.layout = next(); break;
      case '--pad': { const [w, h] = next().split('x').map(Number); o.padW = w; o.padH = h; break; }
      case '--seed': o.seed = Number(next()) >>> 0; break;
      case '--speed': o.speed = Number(next()); break;
      case '--backdrop': o.backdrop = next(); break;
      case '--scale': o.scale = Number(next()); break;
      case '--cols': o.cols = parseInt(next(), 10); break;
      case '--width': o.width = Number(next()); break;
      case '--crop': o.crop = 60; if (argv[i + 1] !== undefined && /^\d+(\.\d+)?$/.test(argv[i + 1])) o.crop = Number(argv[++i]); break;
      case '--t-range': { const [a0, b0] = next().split(':').map(Number); o.t0 = a0; o.t1 = b0; break; }
      case '--quiet': o.quiet = true; break;
      case '--no-notch': o.noNotch = true; break;
      case '--list-themes': o.listThemes = true; break;
      default:
        if (a.startsWith('--')) die(`unknown option ${a}\n\n${HELP}`);
        rest.push(a);
    }
  }
  o.effect = rest[0];
  return o;
}
function die(msg) { console.error(msg); process.exit(2); }

const themes = JSON.parse(fs.readFileSync(path.join(HERE, 'themes.json'), 'utf8'));

function findBrowser() {
  if (process.env.FXLAB_CHROME) return process.env.FXLAB_CHROME;
  const base = path.join(os.homedir(), '.cache', 'ms-playwright');
  const dirs = fs.existsSync(base) ? fs.readdirSync(base) : [];
  for (const d of dirs.filter((x) => x.startsWith('chromium_headless_shell')).sort().reverse()) {
    const p = path.join(base, d, 'chrome-headless-shell-linux64', 'chrome-headless-shell');
    if (fs.existsSync(p)) return p;
  }
  for (const d of dirs.filter((x) => /^chromium-\d+/.test(x)).sort().reverse()) {
    const p = path.join(base, d, 'chrome-linux64', 'chrome');
    if (fs.existsSync(p)) return p;
  }
  die('no Chromium found in ~/.cache/ms-playwright (set FXLAB_CHROME=/path/to/chrome)');
}

const MIME = { '.js': 'text/javascript', '.mjs': 'text/javascript', '.html': 'text/html', '.json': 'application/json', '.png': 'image/png' };

async function main() {
  const o = parseArgs(process.argv.slice(2));
  if (o.listThemes) { for (const t of themes) console.log(`${t.id.padEnd(18)} ${t.name}`); return; }
  if (!o.effect) die(HELP);
  const effectPath = path.resolve(o.effect);
  if (!fs.existsSync(effectPath)) die(`no such file: ${effectPath}`);
  const theme = themes.find((t) => t.id === o.theme);
  if (!theme) die(`unknown theme ${o.theme}; try --list-themes`);
  if (!(o.t !== undefined || o.frames || o.video)) die('say what to render: --t T --out F, --frames N --sheet F / --out-dir D, or --video F');

  let pw;
  // Use a local install if there is one, else the team's shared install in the fx-lab worktree.
  const SHARED = '/home/user/workspace/wt/lab/tools/fxlab/node_modules/playwright-core/index.mjs';
  try { pw = await import('playwright-core'); }
  catch {
    try { pw = await import(SHARED); }
    catch { die(`playwright-core is not installed. Run: npm install --prefix ${HERE}`); }
  }
  const chromium = pw.chromium || pw.default.chromium;

  const browser = await chromium.launch({
    executablePath: findBrowser(), headless: true,
    args: ['--disable-gpu', '--disable-dev-shm-usage', '--no-first-run', '--disable-extensions', '--mute-audio',
      '--renderer-process-limit=1', '--disable-background-timer-throttling'],
  });
  // Make sure Chromium never outlives us, whatever happens.
  let closing = false;
  const shutdown = async (code) => {
    if (closing) return; closing = true;
    try { await Promise.race([browser.close(), new Promise((r) => setTimeout(r, 3000))]); } catch {}
    try { browser.process?.()?.kill('SIGKILL'); } catch {}
    if (code !== undefined) process.exit(code);
  };
  for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, () => shutdown(130));
  process.on('uncaughtException', (e) => { console.error(e); shutdown(1); });
  const watchdog = setTimeout(() => { console.error('fxlab: gave up after 10 minutes'); shutdown(1); }, 10 * 60 * 1000);
  watchdog.unref();

  try {
    const page = await browser.newPage();
    page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') console.error(`[page] ${m.text()}`); });
    page.on('pageerror', (e) => console.error(`[page] ${e.message}`));
    await page.route('http://fxlab.local/**', async (route) => {
      const u = new URL(route.request().url());
      let file;
      if (u.pathname.startsWith('/lab/')) file = path.join(HERE, u.pathname.slice(5));
      else if (u.pathname.startsWith('/file/')) file = decodeURIComponent(u.pathname.slice(5));
      if (!file || !fs.existsSync(file)) return route.fulfill({ status: 404, body: 'not found' });
      // Effect files are re-read every run; no caching.
      return route.fulfill({ status: 200, contentType: MIME[path.extname(file)] || 'application/octet-stream',
        headers: { 'cache-control': 'no-store' }, body: fs.readFileSync(file) });
    });
    await page.goto('http://fxlab.local/lab/page.html');
    await page.waitForFunction(() => window.fxlab && window.fxlab.ready);
    const info = await page.evaluate((opts) => window.fxlab.setup(opts), {
      effectURL: 'http://fxlab.local/file' + encodeURI(effectPath) + '?v=' + Date.now(),
      theme, layout: o.layout, seed: o.seed, speed: o.speed, padW: o.padW, padH: o.padH, floating: o.floating,
      scale: o.scale, backdrop: o.backdrop, noNotch: !!o.noNotch,
    });
    const name = path.basename(effectPath).replace(/\.m?js$/, '');
    const desc = info.kind === 'flight' ? `flight layout=${o.layout}` : `close ${o.floating ? 'floating' : 'docked'} pad=${o.padW}x${o.padH}`;
    console.log(`${name}: ${desc} theme=${o.theme} canvas=${info.size.width}x${info.size.height} duration=${info.scaledDuration.toFixed(3)}s` +
      (info.cells ? ` cells=${info.cells[0]}x${info.cells[1]} (${info.cells[2].toFixed(2)} pt)` : ''));

    let crop = null;
    if (o.crop !== undefined) {
      const m = o.crop, f = info.focus;
      crop = { x: f.x - m, y: f.y - m, width: f.width + 2 * m, height: f.height + 2 * m };
    }
    const stats = [];
    const report = (r) => {
      stats.push(r);
      if (r.error) console.error(`t=${r.t.toFixed(3)} ERROR in draw: ${r.error}`);
      if (!o.quiet) { const s = r.stats; console.log(`  t=${r.t.toFixed(3)} ${r.ms.toFixed(1).padStart(6)} ms  fill ${s.fill} stroke ${s.stroke} pad ${s.drawPad} text ${s.text} layer ${s.layer} blurred ${s.blurred}`); }
    };
    const mkdir = (f) => fs.mkdirSync(path.dirname(path.resolve(f)), { recursive: true });
    const t0 = o.t0 ?? 0, t1 = o.t1 ?? 1;
    const times = o.frames ? Array.from({ length: o.frames }, (_, i) => (o.frames === 1 ? t0 : t0 + (t1 - t0) * i / (o.frames - 1))) : [];

    if (o.t !== undefined) {
      const r = await page.evaluate(([t, c]) => window.fxlab.frame(t, c), [o.t, crop]);
      report(r);
      const out = o.out || `/tmp/fxlab-${name}-${o.t}.png`;
      mkdir(out); fs.writeFileSync(out, Buffer.from(r.png, 'base64'));
      console.log(`wrote ${out}`);
    }
    if (o.outDir) {
      fs.mkdirSync(o.outDir, { recursive: true });
      for (let i = 0; i < times.length; i++) {
        const r = await page.evaluate(([t, c]) => window.fxlab.frame(t, c), [times[i], crop]);
        report(r);
        fs.writeFileSync(path.join(o.outDir, `${name}-${String(i).padStart(3, '0')}.png`), Buffer.from(r.png, 'base64'));
      }
      console.log(`wrote ${times.length} frames to ${o.outDir}`);
    }
    if (o.sheet || (o.frames && !o.outDir && !o.sheet)) {
      const out = o.sheet || `/tmp/fxlab-${name}-sheet.png`;
      const cols = o.cols || (crop ? 4 : 3);
      const cellW = (o.width - 6 * (cols + 1)) / cols;
      const title = `${name}  ${desc}  theme=${o.theme}  backdrop=${o.backdrop}  ${info.scaledDuration.toFixed(2)}s` + (o.compare ? '   (top: fxlab, bottom: Mac)' : '');
      await page.evaluate((a) => window.fxlab.sheetBegin(...a), [times.length, cols, cellW, crop, title, !!o.compare]);
      for (let i = 0; i < times.length; i++) {
        let ref = null;
        if (o.compare) {
          const f = `${o.compare}-${String(i).padStart(3, '0')}.png`;
          if (fs.existsSync(f)) ref = 'data:image/png;base64,' + fs.readFileSync(f).toString('base64');
          else console.error(`no reference frame ${f}`);
        }
        report(await page.evaluate((a) => window.fxlab.sheetAdd(...a), [i, times[i], ref]));
      }
      const png = await page.evaluate(() => window.fxlab.sheetEnd());
      mkdir(out); fs.writeFileSync(out, Buffer.from(png, 'base64'));
      console.log(`wrote ${out}`);
    }
    if (o.video) {
      const n = Math.max(2, Math.round(info.scaledDuration * o.fps) + 1);
      mkdir(o.video);
      const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(o.fps), '-i', '-',
        // A short hold on the first and last frames so the start and end can be seen.
        '-vf', `tpad=start_duration=0.3:stop_duration=0.4:start_mode=clone:stop_mode=clone,pad=ceil(iw/2)*2:ceil(ih/2)*2`,
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-preset', 'veryfast', '-crf', '18', o.video], { stdio: ['pipe', 'inherit', 'inherit'] });
      const done = new Promise((res, rej) => ff.on('close', (c) => (c === 0 ? res() : rej(new Error(`ffmpeg exited ${c}`)))));
      for (let i = 0; i < n; i++) {
        // The last frame is t just below 1: at t = 1 the effect draws nothing.
        const t = Math.min(i / (n - 1), 1);
        const r = await page.evaluate(([t, c]) => window.fxlab.frame(t, c), [t, crop]);
        report(r);
        if (!ff.stdin.write(Buffer.from(r.png, 'base64'))) await new Promise((res) => ff.stdin.once('drain', res));
      }
      ff.stdin.end();
      await done;
      console.log(`wrote ${o.video} (${n} frames at ${o.fps} fps)`);
    }
    if (stats.length) {
      const ms = stats.map((s) => s.ms), calls = stats.map((s) => s.stats.fill + s.stats.stroke + s.stats.drawPad + s.stats.text);
      const worst = stats.reduce((a, b) => (b.ms > a.ms ? b : a));
      const blur = Math.max(...stats.map((s) => s.stats.blurred));
      console.log(`cost: ${stats.length} frames, average ${(ms.reduce((a, b) => a + b, 0) / ms.length).toFixed(1)} ms, worst ${worst.ms.toFixed(1)} ms at t=${worst.t.toFixed(3)}; ` +
        `draw calls per frame: average ${Math.round(calls.reduce((a, b) => a + b, 0) / calls.length)}, most ${Math.max(...calls)}; most blurred draws ${blur}`);
      const errors = stats.filter((s) => s.error).length;
      if (errors) { console.error(`${errors} frame(s) threw errors`); process.exitCode = 1; }
    }
  } finally {
    await shutdown();
  }
}

main().catch((e) => { console.error(e?.stack || e); process.exitCode = 1; });
