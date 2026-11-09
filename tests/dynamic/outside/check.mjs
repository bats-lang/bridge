// Runs dist/debug/app.wasm through the bridge.js that gen wrote with
// produce_bridge_app_book, in jsdom against fake-indexeddb. The app asks for
// URLs of other schemes and for responses whose final URL is not http(s) (a
// stand-in fetch answers them), then keeps the body of one it got in the
// second database (bats-outside): put, get, delete, get again, and a key never
// put. A database "bats" made before the app runs must open unchanged after
// it (same version, same store and record), and bats-outside must hold the one
// store "files" at version 1. Prints what the app logged, then what the
// stand-in fetch was asked.
import 'fake-indexeddb/auto';
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost/', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;

const asked = [];
const answer = (url, body) => ({ ok: true, status: 200, url, headers: { get: () => null }, arrayBuffer: async () => body.buffer.slice(body.byteOffset, body.byteOffset + body.byteLength) });
global.fetch = async (url) => {
  asked.push(String(url));
  switch (String(url)) {
    case 'http://localhost/hello': return answer('http://localhost/hello', new TextEncoder().encode('hello'));
    case 'http://localhost/to-data': return answer('data:text/plain,hello', new TextEncoder().encode('hello'));
    case 'http://localhost/no-url': return answer('', new TextEncoder().encode('hello'));
    default: throw new Error('refused');
  }
};

// a database of the bats package, made before the app runs
await new Promise((resolve, reject) => {
  const req = indexedDB.open('bats', 1);
  req.onupgradeneeded = () => { req.result.createObjectStore('kv'); };
  req.onsuccess = () => {
    const tx = req.result.transaction('kv', 'readwrite');
    tx.objectStore('kv').put(new Uint8Array([7, 8, 9]), 'kept');
    tx.oncomplete = () => { req.result.close(); resolve(); };
  };
  req.onerror = () => reject(req.error);
});

const lines = [];
const consoleLog = console.log;
console.log = (...parts) => lines.push(parts.join(' ').replace(/^\[bats:\w+\] /, ''));

const src = readFileSync('dist/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-outside-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);
await loadWASM(readFileSync('dist/debug/app.wasm'), document.getElementById('bats-root'), {});
await new Promise((r) => setTimeout(r, 500));
console.log = consoleLog;
for (const l of lines) console.log(l);
console.log(`asked: ${asked.join(' ')}`);

const open = (name, version) => new Promise((resolve, reject) => {
  const req = indexedDB.open(name, version);
  req.onsuccess = () => resolve(req.result);
  req.onerror = () => reject(req.error);
});
const old = await open('bats', 1);
console.log(`bats: version ${old.version}, stores ${[...old.objectStoreNames].join(',')}`);
const kept = await new Promise((resolve) => {
  const req = old.transaction('kv').objectStore('kv').get('kept');
  req.onsuccess = () => resolve(req.result);
});
console.log(`bats kept: ${[...kept].join(',')}`);
old.close();
const outside = await open('bats-outside', 1);
console.log(`bats-outside: version ${outside.version}, stores ${[...outside.objectStoreNames].join(',')}`);
outside.close();
const all = await indexedDB.databases();
console.log(`databases: ${all.map((d) => d.name).sort().join(',')}`);
