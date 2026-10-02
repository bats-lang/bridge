// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, serving app.wasm's HEAD with an ETag that changes on the third
// check and plain.wasm's with none, and the 30 seconds between checks
// at once. A check due while the page is hidden waits until it is shown.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
const win = dom.window;
global.document = win.document;
global.window = win;

const heads = { 'app.wasm': 0, 'plain.wasm': 0 };
const etags = ['a', 'a', 'b'];
global.fetch = async (url, init) => {
  const name = String(url);
  if (init && init.method === 'HEAD') heads[name] += 1;
  const etag = name === 'app.wasm' ? etags[Math.min(heads[name], etags.length) - 1] : null;
  return {
    ok: true, status: 200,
    headers: { get: h => (h === 'etag' ? etag : null) },
    arrayBuffer: async () => new ArrayBuffer(0),
  };
};
const setTimeoutReal = global.setTimeout;
global.setTimeout = (f, ms, ...rest) => setTimeoutReal(f, ms === 30000 ? 0 : ms, ...rest);
let visibility = 'visible';
Object.defineProperty(win.document, 'visibilityState', { get: () => visibility, configurable: true });

const lines = [];
const consoleLog = console.log;
console.log = (...parts) => lines.push(parts.join(' '));
const settle = () => new Promise(r => setTimeoutReal(r, 100));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-build-watch-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
// hidden as soon as the first check is done: the next waits to be shown
const first = global.fetch;
global.fetch = async (url, init) => { const r = await first(url, init); if (heads['app.wasm'] === 1) visibility = 'hidden'; return r; };
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await settle();
const report = step => lines.push(`${step}: app.wasm ${heads['app.wasm']} checks, plain.wasm ${heads['plain.wasm']}`);
report('hidden');
visibility = 'visible';
win.document.dispatchEvent(new win.Event('visibilitychange'));
await settle();
report('shown');
console.log = consoleLog;
for (const l of lines) console.log(l);
