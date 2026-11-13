// .tmp/mermaid-validate.mjs - validate every .mmd block in .tmp against mermaid.
// Loads mermaid's ESM dist in a headless Chromium page, calls
// mermaid.parse() per block, and prints PASS/FAIL with the parse error.
import { readdirSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const root = '/home/hamid/dev/sentin8.new/bank8';
const mermaidPath = path.join(root, 'bank8-site/node_modules/mermaid/dist/mermaid.esm.min.mjs');
const require_ = createRequire(import.meta.url);
const chromium = require_('@playwright/test').chromium;

const files = readdirSync(path.join(root, '.tmp')).filter((f) => f.endsWith('.mmd')).sort((a, b) => {
  const na = Number(a.slice(1, -4)); const nb = Number(b.slice(1, -4));
  return na - nb;
});

const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto('about:blank');
await page.addScriptTag({ path: path.join(root, 'bank8-site/node_modules/mermaid/dist/mermaid.min.js') });
await page.evaluate(() => { window.mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' }); });

let fails = 0;
for (const f of files) {
  const meta = readFileSync(path.join(root, '.tmp', f.replace(/\.mmd$/, '.meta')), 'utf8').trim();
  const body = readFileSync(path.join(root, '.tmp', f), 'utf8');
  const res = await page.evaluate(async ({ src }) => {
    try { await window.mermaid.parse(src); return { ok: true }; }
    catch (e) { return { ok: false, err: String(e && e.message || e) }; }
  }, { src: body });
  if (res.ok) {
    console.log(`PASS  ${meta}`);
  } else {
    fails++;
    console.log(`FAIL  ${meta}\n      ${res.err.split('\n').slice(0, 6).join('\n      ')}`);
  }
}
await browser.close();
console.log(fails === 0 ? 'ALL PASS' : `${fails} FAILING BLOCKS`);
process.exit(fails === 0 ? 0 : 1);
