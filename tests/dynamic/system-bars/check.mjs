// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing the native app (quire#300): Capacitor's SystemBars and
// the StatusBar plugin an app may still have, each printing the calls
// made of it. Full screen must hide the system bars (both: no bar
// named) and show them again, never through StatusBar, which hides the
// status bar alone.
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

const plugin = name => {
  const call = method => options => {
    console.log(`${name}.${method}(${options === undefined ? '' : JSON.stringify(options)})`);
    return Promise.resolve();
  };
  return { hide: call('hide'), show: call('show') };
};
globalThis.Capacitor = { isNativePlatform: () => true,
  Plugins: { SystemBars: plugin('SystemBars'), StatusBar: plugin('StatusBar') } };
const settle = () => new Promise(r => setTimeout(r, 100));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-system-bars-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});
await settle();
console.log('done');
