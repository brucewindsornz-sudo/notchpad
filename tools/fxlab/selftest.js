#!/usr/bin/env node
// Checks the hash and random numbers against values computed independently (Python, explicit mod 2^32
// arithmetic, i.e. exactly Swift's &* and &+). Every particle position depends on these.
import { closeHash, CloseRNG, closeNoise } from './fx.js';
const want = [0, 0.5008470041211694, 0.8451132520567626, 0.5125226706732064, 0.10856830701231956, 0.6266081070061773,
  0.9627261769492179, 0.18837198405526578, 0.3504589442163706, 0.08788741892203689, 0.8811728993896395,
  0.26642920868471265, 0.0003297457005828619, 0.7947317505904721];
const got = [];
for (const [i, j, s] of [[0, 0, 0], [1, 2, 3], [-5, 7, 20261128], [123456789, -987654321, 4294967295], [83, 48, 20261128], [2 ** 40 + 3, -(2 ** 35), 77]]) got.push(closeHash(i, j, s));
const r = new CloseRNG(20261128); for (let k = 0; k < 5; k++) got.push(r.next());
const r2 = new CloseRNG(0); got.push(r2.next(), r2.next());
got.push(closeNoise(3.25, -1.75, 20261128));
const bad = got.map((v, i) => (v === want[i] ? null : `#${i}: got ${v}, want ${want[i]}`)).filter(Boolean);
console.log(bad.length ? 'FAIL\n' + bad.join('\n') : `ok: ${got.length} values bit-identical`);
process.exit(bad.length ? 1 : 0);
