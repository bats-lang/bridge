// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, four times: playing the native app with Capacitor's Browser and
// App plugins, with Browser alone, with App alone, and a browser (no
// Capacitor). Browser prints each tab opened, and rejects one address;
// App keeps the address that started the app until a listener is added,
// as Capacitor's appUrlOpen does, then two more come. Each hash the app
// sets is printed.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const settle = () => new Promise(r => setTimeout(r, 300));
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
// bridge.js boots itself at its end; keep only loadWASM
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');

async function run(label, { browser, app, native = true }) {
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
    open: o => {
      console.log(`open: ${o.url}`);
      return o.url.endsWith('/rejected') ? Promise.reject(new Error('no browser')) : Promise.resolve();
    },
  };
  if (app) plugins.App = {
    addListener: (name, f) => {
      console.log(`addListener: ${name}`);
      listeners.push(f);
      setTimeout(() => retained.splice(0).forEach(e => f(e)), 10);
      return Promise.resolve({ remove: () => Promise.resolve() });
    },
  };
  if (native) globalThis.Capacitor = { isNativePlatform: () => true, Plugins: plugins };
  else delete globalThis.Capacitor;
  win.addEventListener('hashchange', e => console.log(`hash: ${new URL(e.newURL).hash}`));
  // a fresh module each run: its listener state is the run's own
  const tmp = join(tmpdir(), `bridge-app-link-${process.pid}-${label}.mjs`);
  writeFileSync(tmp, src.slice(0, boot) + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});
  await settle();
  for (const url of ['quire://oauth/dropbox?code=c&state=s', '']) {
    console.log(`appUrlOpen: ${url}`);
    listeners.forEach(f => f({ url }));
    await settle();
  }
}

await run('both', { browser: true, app: true });
await run('browser', { browser: true, app: false });
await run('app', { browser: false, app: true });
await run('browser page', { browser: false, app: false, native: false });
