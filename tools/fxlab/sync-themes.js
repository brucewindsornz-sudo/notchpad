#!/usr/bin/env node
// Copies the built-in theme list out of Sources/Themes.swift into themes.json.
// Run it again whenever Themes.swift changes: node tools/fxlab/sync-themes.js [path/to/Themes.swift]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const src = process.argv[2] || path.join(HERE, '..', '..', 'Sources', 'Themes.swift');
const text = fs.readFileSync(src, 'utf8');
const start = text.indexOf('static let builtIn');
if (start < 0) throw new Error('no builtIn list in ' + src);
const body = text.slice(start);
const out = [];
// t("id", "Name", "#bg", "#fg", "#accent", "#sel") and signature("id", "Name", ..., fonts: [...], fallback: .x, key: value...)
const re = /\b(t|signature)\(\s*("(?:[^"\\]|\\.)*")\s*,\s*("(?:[^"\\]|\\.)*")\s*,\s*"(#[0-9a-fA-F]+)"\s*,\s*"(#[0-9a-fA-F]+)"\s*,\s*"(#[0-9a-fA-F]+)"\s*,\s*"(#[0-9a-fA-F]+)"([^)]*(?:\[[^\]]*\][^)]*)*)\)/g;
let m;
while ((m = re.exec(body))) {
  const theme = { id: JSON.parse(m[2]), name: JSON.parse(m[3]), background: m[4], text: m[5], accent: m[6], selection: m[7] };
  if (m[1] === 'signature') {
    const rest = m[8];
    const fonts = /fonts:\s*\[([^\]]*)\]/.exec(rest);
    if (fonts) theme.fonts = [...fonts[1].matchAll(/"([^"]*)"/g)].map((x) => x[1]);
    const fb = /fallback:\s*\.(\w+)/.exec(rest); if (fb) theme.fallback = fb[1];
    const face = /face:\s*\.(\w+)/.exec(rest); if (face) theme.face = face[1];
    for (const k of ['scale', 'leading', 'tracking']) { const v = new RegExp(k + ':\\s*([0-9.]+)').exec(rest); if (v) theme[k] = Number(v[1]); }
    const glow = /glow:\s*"(#[0-9a-fA-F]+)"/.exec(rest); if (glow) theme.glow = glow[1];
    const close = /close:\s*"(\w+)"/.exec(rest); if (close) theme.close = close[1];
    theme.signature = true;
  }
  out.push(theme);
}
if (!out.length) throw new Error('found no themes');
fs.writeFileSync(path.join(HERE, 'themes.json'), JSON.stringify(out, null, 1) + '\n');
console.log(`themes.json: ${out.length} themes from ${src}`);
