// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, twice: playing the native app with Capacitor's App plugin, and
// a browser (no Capacitor). App prints each listener added and each
// minimizeApp; Back is pressed three times (each press calls the
// backButton listeners, as App does). Each hash the app sets is
// printed.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const settle = () => new Promise(r => setTimeout(r, 300));
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
// bridge.js boots itself at its end; keep only loadWASM
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');

async function run(label, { native }) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  const listeners = [];
  const plugins = {
    App: {
      addListener: (name, f) => {
        console.log(`addListener: ${name}`);
        if (name === 'backButton') listeners.push(f);
        return Promise.resolve({ remove: () => Promise.resolve() });
      },
      minimizeApp: () => { console.log('minimizeApp'); return Promise.resolve(); },
    },
  };
  if (native) globalThis.Capacitor = { isNativePlatform: () => true, Plugins: plugins };
  else delete globalThis.Capacitor;
  win.addEventListener('hashchange', e => console.log(`hash: ${new URL(e.newURL).hash}`));
  win.addEventListener('popstate', () => console.log(`popstate: ${win.location.hash}`));
  const tmp = join(tmpdir(), `bridge-back-button-${process.pid}-${label}.mjs`);
  writeFileSync(tmp, src.slice(0, boot) + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});
  await settle();
  for (let i = 0; i < 3; i++) {
    console.log('back');
    listeners.forEach(f => f({ canGoBack: false }));
    await settle();
  }
}

await run('app', { native: true });
await run('browser', { native: false });
