// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, once for each platform the rotation lock meets (quire#355): the
// app's ScreenOrientation plugin (which locks, or rejects with an error of
// each form), a WebView that also has screen.orientation.lock and a
// standalone display mode (the plugin is used, the web API never), a
// browser that can lock (full screen) and one that cannot, and a plugin
// that goes away between the question and the lock. Each prints the
// calls made and how the lock ended (the app's hash).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-orientation-lock-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
let { loadWASM } = await import(tmp);
unlinkSync(tmp);
// The same bridge.js with the one code it never gives (3) where the
// refusal's 2 was, to pass LockUnexpected through the app
const odd = src.slice(0, boot).replace('lockTexts.set(id, pendBlob(utf8.encode(text)));\n    } catch (e) {}\n    return 2;', 'lockTexts.set(id, pendBlob(utf8.encode(text)));\n    } catch (e) {}\n    return 3;');
if (odd === src.slice(0, boot)) throw new Error('bridge.js: lockRefused not found');
const tmpOdd = join(tmpdir(), `bridge-orientation-lock-odd-${process.pid}.mjs`);
writeFileSync(tmpOdd, odd + '\n');
const loadOdd = (await import(tmpOdd)).loadWASM;
unlinkSync(tmpOdd);
const loadReal = loadWASM;
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

async function play(label, { plugin, web, standalone, fullscreen, plugins, odd }) {
  loadWASM = odd ? loadOdd : loadReal;
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  if (web) {
    Object.defineProperty(win.screen, 'orientation', { configurable: true, value: {
      type: 'landscape-primary',
      lock: o => { console.log(`web lock(${o})`); return web(); },
      unlock: () => console.log('web unlock'),
    } });
    win.matchMedia = q => ({ matches: !!standalone && q.includes('standalone') });
    if (fullscreen) Object.defineProperty(win.document, 'fullscreenElement', { configurable: true, value: win.document.body });
  }
  if (plugin || plugins) {
    const lock = o => { console.log(`plugin lock(${JSON.stringify(o)})`); return plugin(); };
    const found = { lock, unlock: () => Promise.resolve() };
    globalThis.Capacitor = { isNativePlatform: () => true,
      Plugins: plugins ? { get ScreenOrientation() { return plugins(found); } } : { ScreenOrientation: found } };
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

await play('the plugin locks to the orientation the screen has',
  { plugin: () => Promise.resolve() });
await play('in the WebView the plugin is used, never the web API that is also there',
  { plugin: () => Promise.resolve(), web: () => Promise.reject(clean(new Error('NotSupportedError'))), standalone: true, fullscreen: true });
await play('the plugin rejects with an Error: its name, message and code are kept',
  { plugin: () => Promise.reject(clean(Object.assign(new Error('not allowed'), { code: 'UNIMPLEMENTED' }))) });
await play('the plugin rejects with a string',
  { plugin: () => Promise.reject('refused as text') });
await play('the plugin rejects with nothing',
  { plugin: () => Promise.reject(undefined) });
await play('the plugin throws',
  { plugin: () => { throw clean(new Error('threw')); } });
await play('a browser that can lock (full screen) locks through the web API',
  { web: () => Promise.resolve(), fullscreen: true });
await play('a browser that can lock, refused: the error is kept',
  { web: () => Promise.reject(clean(new DOMException('not full screen', 'NotSupportedError'))), fullscreen: true });
await play('a browser that cannot lock does not offer it', {});
let asks = 0;
await play('the plugin is there for the question and gone for the lock: unavailable, not refused',
  { plugin: () => Promise.resolve(), plugins: found => (++asks <= 1 ? found : undefined) });
await play('a code the bridge never gives is LockUnexpected',
  { plugin: () => Promise.reject(new Error('x')), odd: true });
console.log('done');
