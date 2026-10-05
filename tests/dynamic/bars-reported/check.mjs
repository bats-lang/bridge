// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, twice: playing the native app, whose activity reports the
// system bars through batsNative.systemBars (one report before the app
// listens, then the system hiding and showing them), and a browser,
// which reports none. Each hash the app sets is printed.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const settle = () => new Promise(r => setTimeout(r, 100));
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
// bridge.js boots itself at its end; keep only loadWASM
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');

async function run(label, reports) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  delete globalThis.batsSystemBars;
  delete globalThis.batsSystemBarsChanged;
  win.addEventListener('hashchange', e => console.log(`hash: ${new URL(e.newURL).hash}`));
  // a fresh module each run: its listener state is the run's own
  const tmp = join(tmpdir(), `bridge-bars-reported-${process.pid}-${label}.mjs`);
  writeFileSync(tmp, src.slice(0, boot) + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  const report = (status, navigation) => {
    console.log(`systemBars(${status}, ${navigation}): ${globalThis.batsNative.systemBars(status, navigation)}`);
  };
  // the report the activity makes as the page loads, before the app listens
  if (reports) report(true, true);
  await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});
  await settle();
  if (!reports) return;
  for (const [status, navigation] of [[false, false], [true, false], [false, true], [true, true]]) {
    report(status, navigation);
    await settle();
  }
}

await run('app', true);
await run('browser', false);
