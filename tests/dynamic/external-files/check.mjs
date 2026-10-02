// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom: the native app hands a URL before the bridge loads, the system
// opens the app with a file (launchQueue), and the native app hands a
// URL that is not there; prints what the app logged, in order.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;
global.fetch = async (url) => (String(url) === '/doc.epub'
  ? { ok: true, status: 200, headers: { get: () => null }, arrayBuffer: async () => new Uint8Array([1, 2, 3]).buffer }
  : { ok: false, status: 404, headers: { get: () => null }, arrayBuffer: async () => new ArrayBuffer(0) });
let consumer = null;
global.launchQueue = { setConsumer: (f) => { consumer = f; } };
const lines = [];
const consoleLog = console.log;
console.log = (...parts) => lines.push(parts.join(' '));

// bridge.js boots itself at its end; keep only loadWASM (and the early
// code, which defines batsNative)
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-external-files-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

globalThis.batsNative.deliverFile('/doc.epub', 'Doc.epub');
const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await new Promise(r => setTimeout(r, 50));
consumer({ files: [{ getFile: async () => ({ name: 'notes.txt', arrayBuffer: async () => new Uint8Array([4, 5, 6]).buffer }) }] });
await new Promise(r => setTimeout(r, 50));
globalThis.batsNative.deliverFile('/missing', 'Gone.epub');
await new Promise(r => setTimeout(r, 100));
console.log = consoleLog;
for (const l of lines) console.log(l);
