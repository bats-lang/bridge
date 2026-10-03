// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing document.fonts (jsdom has none): a load ends while
// another is still loading, then the last one ends. Prints what the
// app logged, in order.
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
const fonts = new win.EventTarget();
fonts.status = 'loaded';
Object.defineProperty(win.document, 'fonts', { value: fonts, configurable: true });
const lines = [];
const consoleLog = console.log;
console.log = (...parts) => lines.push(parts.join(' '));
const settle = () => new Promise(r => setTimeout(r, 50));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-fonts-loaded-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await settle();
fonts.status = 'loading';
fonts.dispatchEvent(new win.Event('loadingdone'));
await settle();
fonts.status = 'loaded';
fonts.dispatchEvent(new win.Event('loadingdone'));
await settle();
// a failed load is not a load done: nothing is logged
fonts.dispatchEvent(new win.Event('loadingerror'));
await settle();
console.log = consoleLog;
for (const l of lines) console.log(l);
