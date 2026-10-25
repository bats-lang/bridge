// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with navigator.share (a browser) or Capacitor's Share (the native
// app) as each case plays it. The app shares a text with share_text_answer
// and then, again, with the old share_text. The cases: the share sheet takes
// it; it is closed (an AbortError, and the Share plugin's "Share canceled");
// the failures the Web Share API documents (NotAllowedError, DataError,
// TypeError); a rejection that is neither (with an error, with an error
// whose message only says cancel, and with nothing); the share throws as it
// is called (with an error and with nothing); there is no way to share; the
// text failing to read; and a code the bridge never gives. Prints each
// share made and what the app says: the outcome of share_text_answer (every
// constructor) and of the old share_text, which says only shared, cancelled
// or failed (bridge#186, bridge#241). The old form's outcome differs from
// before for one case, pinned here: a rejection that only says cancel in
// its message is a failure, where the old JS took it for a cancel.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-share-text-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with the text failing to read (the app cannot make it
// fail, the wasm memory is there), and with a code it never gives (7) where
// a share had 0, to pass the thrown reading and TextAnswerUnexpected
// through the app
const textRead = '{ text: readString(xp, xl) }';
if (!head.includes(textRead)) throw new Error('bridge.js: the text read not found');
const sharedCode = 'Promise.resolve(p).then(() => 0, e => shareEnd(id, e))';
if (!head.includes(sharedCode)) throw new Error('bridge.js: the shared case not found');
const loads = {
  real: await load('real', head),
  unreadable: await load('unreadable', head.replace(textRead,
    "{ text: (() => { throw (e => { delete e.stack; return e; })(new Error('text unreadable')); })() }")),
  unexpected: await load('unexpected', head.replace(sharedCode, 'Promise.resolve(p).then(() => 7, e => shareEnd(id, e))')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths, and with
// the name a platform gives
const named = (name, message) => { const e = new Error(message); e.name = name; delete e.stack; return e; };
const clean = e => { delete e.stack; return e; };

// share: how the page shares ('web' navigator.share, 'app' Capacitor's
// Share, or nothing)
async function play(label, share, { where = 'web', bridge = 'real' } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  const call = d => { console.log(`share ${JSON.stringify(d)}`); return share(d); };
  Object.defineProperty(global, 'navigator', { value: where === 'web' ? { share: call } : {}, configurable: true });
  if (where === 'app') globalThis.Capacitor = { isNativePlatform: () => true, Plugins: { Share: { share: call } } };
  else delete globalThis.Capacitor;
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

await play('the share sheet takes it', () => Promise.resolve());
await play('the user closes the share sheet: an AbortError', () => Promise.reject(named('AbortError', 'Share canceled by the user')));
await play('NotAllowedError: a failure the API documents', () => Promise.reject(named('NotAllowedError', 'no activation')));
await play('DataError: a failure the API documents', () => Promise.reject(named('DataError', 'bad data')));
await play('TypeError: a failure the API documents', () => Promise.reject(named('TypeError', 'cannot share')));
await play('a rejection the API does not document: its own outcome, with the error',
  () => Promise.reject(clean(new Error('sharing is in progress'))));
await play('a rejection whose message only says cancel is no cancel',
  () => Promise.reject(clean(new Error('Share cancelled'))));
await play('a rejection with nothing', () => Promise.reject());
await play('the share throws as it is called: its own outcome, with the error',
  () => { throw clean(new Error('threw')); });
await play('the share throws nothing', () => { throw undefined; });
await play('the app: the Share plugin takes it', () => Promise.resolve({ activityType: '' }), { where: 'app' });
await play('the app: the Share plugin says "Share canceled"', () => Promise.reject(clean(new Error('Share canceled'))), { where: 'app' });
await play('the app: the Share plugin rejects otherwise',
  () => Promise.reject(clean(new Error("Can't share while sharing is in progress"))), { where: 'app' });
await play('there is no way to share here', () => Promise.resolve(), { where: 'none' });
await play('the text fails to read: a thrown share', () => Promise.resolve(), { bridge: 'unreadable' });
await play('a code the bridge never gives is TextAnswerUnexpected', () => Promise.resolve(), { bridge: 'unexpected' });
console.log('done');
