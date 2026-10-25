// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing the native app: Capacitor with Browser, whose open each
// case plays differently. The app opens an https address and then one that
// is not, each with browser_tab_open_answer and then with the old
// browser_tab_open. The cases: the plugin opens the tab (with an answer and
// with none); it rejects the open (with an error and with nothing); the open
// throws as it is called (with an error and with nothing); the app has no
// Browser plugin; the address failing to read; and a code the bridge never
// gives. Prints each open made and what the app says: the outcome of
// browser_tab_open_answer (every constructor, an address that is not https
// included) and of the old browser_tab_open, which says only opened or not
// opened (bridge#186, bridge#240).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-browser-tab-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with the address failing to read (the app cannot make
// it fail, the wasm memory is there), and with a code it never gives (-9)
// where a rejection had -2, to pass the thrown reading and
// TabOpenUnexpected through the app
const addressRead = 'url: readString(up, ul)';
if (!head.includes(addressRead)) throw new Error('bridge.js: the address read not found');
const rejectedCode = 'browserTabSaid(id, x, -2)';
if (!head.includes(rejectedCode)) throw new Error('bridge.js: the rejection case not found');
const loads = {
  real: await load('real', head),
  unreadable: await load('unreadable', head.replace(addressRead,
    "url: (() => { throw (e => { delete e.stack; return e; })(new Error('address unreadable')); })()")),
  unexpected: await load('unexpected', head.replace(rejectedCode, 'browserTabSaid(id, x, -9)')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

async function play(label, open, { plugins = true, bridge = 'real' } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  globalThis.Capacitor = {
    isNativePlatform: () => true,
    Plugins: plugins ? { Browser: { open: o => { console.log(`open ${o.url}`); return open(o); } } } : {},
  };
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

await play('the plugin opens the tab', () => Promise.resolve());
await play('the plugin opens the tab and answers something', () => Promise.resolve({ opened: true }));
await play('the plugin rejects the open: its own outcome, with the error',
  () => Promise.reject(clean(new Error('no tab'))));
await play('the plugin rejects with nothing', () => Promise.reject());
await play('the open throws as it is called: its own outcome, with the error',
  () => { throw clean(new Error('threw')); });
await play('the open throws nothing', () => { throw undefined; });
await play('there is no Browser plugin', () => Promise.resolve(), { plugins: false });
await play('the address fails to read: a thrown open', () => Promise.resolve(), { bridge: 'unreadable' });
await play('a code the bridge never gives is TabOpenUnexpected',
  () => Promise.reject(clean(new Error('x'))), { bridge: 'unexpected' });
console.log('done');
