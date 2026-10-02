// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing the browser's wake lock: each request is granted, a
// hidden page drops the lock, and the app asks again once it is shown.
// Prints each step's requests and releases.
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

let requests = 0, releases = 0, held = null;
function lock() {
  const listeners = [];
  return {
    addEventListener: (_, f) => listeners.push(f),
    release() { releases += 1; listeners.forEach(f => f()); return Promise.resolve(); },
    drop() { listeners.forEach(f => f()); },
  };
}
Object.defineProperty(global, 'navigator', {
  value: { wakeLock: { request: () => { requests += 1; held = lock(); return Promise.resolve(held); } } },
  configurable: true,
});
let visibility = 'visible';
Object.defineProperty(win.document, 'visibilityState', { get: () => visibility, configurable: true });
const settle = () => new Promise(r => setTimeout(r, 50));
const say = step => console.log(`${step}: requests ${requests}, releases ${releases}`);

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-wake-lock-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await settle();
say('wanted');
// hidden: the browser drops the lock; a hidden page is not asked for one
visibility = 'hidden';
held.drop();
win.document.dispatchEvent(new win.Event('visibilitychange'));
await settle();
say('hidden');
visibility = 'visible';
win.document.dispatchEvent(new win.Event('visibilitychange'));
await settle();
say('shown');
// shown again with the lock held: no second request
win.document.dispatchEvent(new win.Event('visibilitychange'));
await settle();
say('shown again');
win.document.dispatchEvent(new win.Event('sleep'));
await settle();
say('not wanted');
visibility = 'hidden';
win.document.dispatchEvent(new win.Event('visibilitychange'));
visibility = 'visible';
win.document.dispatchEvent(new win.Event('visibilitychange'));
await settle();
say('shown, not wanted');
