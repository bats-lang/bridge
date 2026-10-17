// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with the app's ScreenBrightness plugin as each case plays it: an
// answer that reads, a rejection, an answer whose brightness getter throws
// when the bridge reads it (the bridge's ok handler throws, so the call
// must still settle, quire#152's settleBy), and no plugin. Each prints the
// call made and the reading the app says (the address's hash).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-brightness-settle-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

async function play(label, plugins) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  if (plugins) {
    globalThis.Capacitor = { isNativePlatform: () => true, Plugins: { ScreenBrightness: plugins } };
  } else {
    globalThis.Capacitor = undefined;
  }
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  await loadWASM(wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

const getBrightness = answer => () => { console.log('plugin getBrightness()'); return answer(); };
const noop = () => Promise.resolve();

await play('the plugin answers the brightness it has',
  { getBrightness: getBrightness(() => Promise.resolve({ brightness: 0.5 })), setBrightness: noop });
await play('the plugin answers, and reading the answer throws: the read still settles',
  { getBrightness: getBrightness(() => Promise.resolve({ get brightness() { throw clean(new Error('no brightness')); } })), setBrightness: noop });
await play('the plugin rejects the read',
  { getBrightness: getBrightness(() => Promise.reject(clean(new Error('denied')))), setBrightness: noop });
await play('the app has no ScreenBrightness plugin', null);
console.log('done');
