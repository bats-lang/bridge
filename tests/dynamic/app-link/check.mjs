// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing the native app: Capacitor with its Browser (each tab
// opened and closed is printed) and App (an address that started the
// app is kept until a listener is added, as Capacitor's appUrlOpen is;
// then two more come). Prints each call.
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

const listeners = [];
// the address that started the app, kept until a listener takes it
const retained = [{ url: 'https://example.com/started' }];
globalThis.Capacitor = {
  isNativePlatform: () => true,
  Plugins: {
    Browser: {
      open: o => { console.log(`open: ${o.url}`); return Promise.resolve(); },
      close: () => { console.log('close'); return Promise.resolve(); },
    },
    App: {
      addListener: (name, f) => {
        console.log(`addListener: ${name}`);
        listeners.push(f);
        setTimeout(() => retained.splice(0).forEach(e => f(e)), 10);
        return Promise.resolve({ remove: () => Promise.resolve() });
      },
    },
  },
};
const settle = () => new Promise(r => setTimeout(r, 300));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-app-link-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await settle();
for (const url of ['quire://oauth/dropbox?code=c&state=s', '', 'https://example.com/back?code=1']) {
  console.log(`appUrlOpen: ${url}`);
  listeners.forEach(f => f({ url }));
  await settle();
}
