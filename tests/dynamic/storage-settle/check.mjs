// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with navigator.storage as each case plays it: an answer yes or no,
// a rejection, a call that throws as it is made, an answer that is no
// boolean, a code the bridge never gives, and the app (storage always
// kept). Each prints the platform call made and what the app says: the
// outcome of storage_persisted_answer (every constructor) and of the old
// storage_persisted, which says only yes or no (bridge#186, bridge#227).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-storage-settle-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
let { loadWASM } = await import(tmp);
unlinkSync(tmp);
// The same bridge.js with a code it never gives (-9) where the answer that
// is no boolean had -4, to pass PersistUnexpected through the app
const odd = src.slice(0, boot).replace('storageSaid(id, v, -4)', 'storageSaid(id, v, -9)');
if (odd === src.slice(0, boot)) throw new Error('bridge.js: the odd answer case not found');
const tmpOdd = join(tmpdir(), `bridge-storage-settle-odd-${process.pid}.mjs`);
writeFileSync(tmpOdd, odd + '\n');
const loadOdd = (await import(tmpOdd)).loadWASM;
unlinkSync(tmpOdd);
const loadReal = loadWASM;
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

async function play(label, storage, { native = false, unexpected = false } = {}) {
  loadWASM = unexpected ? loadOdd : loadReal;
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  Object.defineProperty(global, 'navigator', { value: { storage }, configurable: true });
  globalThis.Capacitor = native ? { isNativePlatform: () => true, Plugins: {} } : undefined;
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  await loadWASM(wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

const persisted = answer => ({ persisted: () => { console.log('storage.persisted()'); return answer(); } });

await play('the platform says the storage is kept',
  persisted(() => Promise.resolve(true)));
await play('the platform says it is not kept',
  persisted(() => Promise.resolve(false)));
await play('the platform rejects: its own outcome, with the error',
  persisted(() => Promise.reject(clean(Object.assign(new Error('denied'), { code: 'SecurityError' })))));
await play('the platform rejects with nothing',
  persisted(() => Promise.reject(undefined)));
await play('the platform throws as it is called',
  persisted(() => { throw clean(new Error('threw')); }));
// The one place the old storage_persisted differs from the old JS (`v ? 1 : 0`):
// an answer the platform never gives, a truthy non-boolean. StorageManager
// documents a Promise of a boolean only, for which the old and the new agree
// (the first two cases). The old JS wrote 'yes' and 1 as Persisted; now they
// are PersistAnswerOdd and the old form says NotPersisted, because JS decides
// nothing and the truthiness is not moved to Bats (bridge#218).
await play('the platform answers something that is no boolean',
  persisted(() => Promise.resolve('yes')));
await play('the platform answers a number that is truthy',
  persisted(() => Promise.resolve(1)));
await play('the platform answers nothing',
  persisted(() => Promise.resolve(undefined)));
await play('a code the bridge never gives is PersistUnexpected',
  persisted(() => Promise.resolve('yes')), { unexpected: true });
await play('the app: its storage is always kept (the platform is not asked)',
  persisted(() => Promise.resolve(false)), { native: true });
console.log('done');
