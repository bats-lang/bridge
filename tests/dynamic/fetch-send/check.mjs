// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with fetch recording each request's method, URL, headers and
// body (answering /a with an ETag, /b with an empty one, the rest with
// none); prints them and what the app logged.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;

const lines = [];
global.fetch = async (url, init) => {
  const headers = (init.headers || []).map(([n, v]) => `${n}=${v}`).join(' ');
  const body = init.body ? new TextDecoder().decode(init.body) : '';
  lines.push(`${init.method} ${url} [${headers}] ${body} cache=${init.cache}`);
  const etag = { '/a': '"e9"', '/b': '' }[url] ?? null;
  return { ok: true, status: 200, headers: { get: h => (h === 'ETag' ? etag : null) }, arrayBuffer: async () => new ArrayBuffer(1) };
};
const consoleLog = console.log;
console.log = (...parts) => lines.push(parts.join(' '));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-fetch-send-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await new Promise(r => setTimeout(r, 100));
console.log = consoleLog;
for (const l of lines.sort()) console.log(l);
