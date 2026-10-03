// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, three times, playing the native app: with Capacitor's Browser
// and App plugins, with Browser alone, and with App alone. Browser
// prints each tab opened; App keeps the address that started the app
// until a listener is added, as Capacitor's appUrlOpen does, then two
// more come. The page's hash, which the app sets, is printed after each
// step.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const settle = () => new Promise(r => setTimeout(r, 300));
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
// bridge.js boots itself at its end; keep only loadWASM
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');

async function run(label, { browser, app }) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  const listeners = [];
  // the address that started the app, kept until a listener takes it
  const retained = [{ url: 'quire://oauth/started' }];
  const plugins = {};
  if (browser) plugins.Browser = {
    open: o => { console.log(`open: ${o.url}`); return Promise.resolve(); },
  };
  if (app) plugins.App = {
    addListener: (name, f) => {
      console.log(`addListener: ${name}`);
      listeners.push(f);
      setTimeout(() => retained.splice(0).forEach(e => f(e)), 10);
      return Promise.resolve({ remove: () => Promise.resolve() });
    },
  };
  globalThis.Capacitor = { isNativePlatform: () => true, Plugins: plugins };
  // a fresh module each run: its listener state is the run's own
  const tmp = join(tmpdir(), `bridge-app-link-${process.pid}-${label}.mjs`);
  writeFileSync(tmp, src.slice(0, boot) + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});
  console.log(`hash: ${win.location.hash}`);
  await settle();
  console.log(`hash: ${win.location.hash}`);
  for (const url of ['quire://oauth/dropbox?code=c&state=s', '']) {
    console.log(`appUrlOpen: ${url}`);
    listeners.forEach(f => f({ url }));
    await settle();
    console.log(`hash: ${win.location.hash}`);
  }
}

await run('both', { browser: true, app: true });
await run('browser', { browser: true, app: false });
await run('app', { browser: false, app: true });
