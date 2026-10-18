// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with the app's ScreenBrightness plugin as each case plays it: an
// answer that reads, a rejection, an answer whose brightness getter throws
// when the bridge reads it (the bridge's ok handler throws: its own outcome,
// with what was thrown, bridge#186), and no plugin. Each prints the
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
let { loadWASM } = await import(tmp);
unlinkSync(tmp);
// The same bridge.js with a code it never gives (-9) where the thrown
// answer's -4 was, to pass BrightnessUnexpected through the app
const odd = src.slice(0, boot).replace('brightnessSaid(id, x, -4)', 'brightnessSaid(id, x, -9)');
if (odd === src.slice(0, boot)) throw new Error('bridge.js: the answer thrown case not found');
const tmpOdd = join(tmpdir(), `bridge-brightness-settle-odd-${process.pid}.mjs`);
writeFileSync(tmpOdd, odd + '\n');
const loadOdd = (await import(tmpOdd)).loadWASM;
unlinkSync(tmpOdd);
const loadReal = loadWASM;
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

async function play(label, plugins, odd) {
  loadWASM = odd ? loadOdd : loadReal;
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
await play('the plugin answers, and reading the answer throws: its own outcome, with what it threw',
  { getBrightness: getBrightness(() => Promise.resolve({ get brightness() { throw clean(new Error('no brightness')); } })), setBrightness: noop });
await play('the plugin answers nothing: reading it throws a TypeError',
  { getBrightness: getBrightness(() => Promise.resolve(undefined)), setBrightness: noop });
await play('the plugin rejects the read: its own outcome, with the error',
  { getBrightness: getBrightness(() => Promise.reject(clean(Object.assign(new Error('denied'), { code: 'UNAVAILABLE' })))), setBrightness: noop });
await play('the plugin rejects with nothing',
  { getBrightness: getBrightness(() => Promise.reject(undefined)), setBrightness: noop });
await play('the plugin throws as it is called',
  { getBrightness: getBrightness(() => { throw clean(new Error('threw')); }), setBrightness: noop });
await play('the app has no ScreenBrightness plugin', null);
await play('a code the bridge never gives is BrightnessUnexpected',
  { getBrightness: getBrightness(() => Promise.resolve(undefined)), setBrightness: noop }, true);
console.log('done');
