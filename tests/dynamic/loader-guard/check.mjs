// Runs the whole of the bridge.js that pwa generated (its loader too) in
// jsdom, once for each way the load of app.wasm can go: it loads; the
// network fails; the server answers 404; the file is damaged; the fetch
// is aborted; and the page is going away (pagehide) when the fetch
// fails. Prints what the root holds after each, what was logged as an
// error, and whether anything escaped as an unhandled rejection; then
// clicks Try again.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const lines = [];
const consoleLog = console.log;
const consoleError = console.error;
const consoleInfo = console.info;
console.log = (...parts) => lines.push(parts.join(' '));
console.info = (...parts) => lines.push(parts.join(' '));
let errors = 0;
console.error = () => { errors += 1; };
let escaped = 0;
process.on('unhandledRejection', () => { escaped += 1; });
let reloads = 0;
global.location = { reload: () => { reloads += 1; } };

const wasm = readFileSync('dist/pwa/app.wasm');
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const answers = {
  loads: async () => ({ ok: true, status: 200, arrayBuffer: async () => wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.length) }),
  offline: async () => { throw new TypeError('Failed to fetch'); },
  'not found': async () => ({ ok: false, status: 404, arrayBuffer: async () => new ArrayBuffer(0) }),
  damaged: async () => ({ ok: true, status: 200, arrayBuffer: async () => new Uint8Array([0, 97, 115, 109, 9]).buffer }),
  aborted: async () => { throw new DOMException('The user aborted a request.', 'AbortError'); },
  'page going away': async () => { window.dispatchEvent(new window.Event('pagehide')); throw new TypeError('Failed to fetch'); },
};

let n = 0;
for (const [name, answer] of Object.entries(answers)) {
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root">Loading</div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  global.window = dom.window;
  global.document = dom.window.document;
  global.fetch = answer;
  errors = 0;
  n += 1;
  const tmp = join(tmpdir(), `bridge-loader-guard-${process.pid}-${n}.mjs`);
  writeFileSync(tmp, src);
  await import(tmp);
  unlinkSync(tmp);
  await new Promise(r => setTimeout(r, 50));
  const root = document.getElementById('bats-root');
  lines.push(`${name}: ${root.innerHTML} (errors logged: ${errors})`);
  const again = root.querySelector('button');
  if (again) {
    again.click();
    lines.push(`${name}: Try again reloads ${reloads}`);
    reloads = 0;
  }
}
lines.push(`escaped: ${escaped}`);
console.log = consoleLog;
console.error = consoleError;
console.info = consoleInfo;
for (const l of lines) console.log(l);
