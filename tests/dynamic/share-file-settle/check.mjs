// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with navigator.share and canShare (a browser) or Capacitor's Share
// and Filesystem (the native app: the file is written to the cache and its
// uri shared) as each case plays it. The app shares a file with
// share_file_answer and then, again, with the old share_file. The cases: the
// share sheet takes it; it is closed (an AbortError, and the Share plugin's
// "Share canceled"); a failure the Web Share API documents; a rejection that
// is not documented; the share throws as it is called; in the app, the write
// to the cache rejecting (with an error and with nothing), throwing,
// answering nothing, and the Share plugin rejecting; a platform that cannot
// share the file (a browser that cannot, an app missing a plugin); the file's
// bytes failing to read; and a code the bridge never gives. Prints each write
// and share made and what the app says: the outcome of share_file_answer
// (every constructor) and of the old share_file, which says only shared,
// cancelled, failed or not shareable (bridge#186, bridge#242).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-share-file-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with the bytes failing to read (the app cannot make
// them fail, the wasm memory is there), and with a code it never gives (-9)
// where the cache write's rejection had -4, to pass the thrown reading and
// FileAnswerUnexpected through the app
const bytesRead = 'bytes = readBytes(bp, bl);';
if (!head.includes(bytesRead)) throw new Error('bridge.js: the bytes read not found');
const cacheCode = 'x => shareSaid(id, x, -4)';
if (!head.includes(cacheCode)) throw new Error('bridge.js: the cache case not found');
const loads = {
  real: await load('real', head),
  unreadable: await load('unreadable', head.replace(bytesRead,
    "bytes = (() => { throw (e => { delete e.stack; return e; })(new Error('bytes unreadable')); })();")),
  unexpected: await load('unexpected', head.replace(cacheCode, 'x => shareSaid(id, x, -9)')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths, and with
// the name a platform gives
const named = (name, message) => { const e = new Error(message); e.name = name; delete e.stack; return e; };
const clean = e => { delete e.stack; return e; };
const shown = d => JSON.stringify({ ...d, files: (d.files || []).map(f => f && f.name !== undefined ? `${f.name} (${f.type}, ${f.size} bytes)` : f) });

// where: 'web' (navigator.share and canShare say yes), 'web-no' (canShare says
// no), 'app' (Capacitor's Share and Filesystem), 'app-no-share' and
// 'app-no-files' (one plugin missing). share is what the share does; write
// what the Filesystem's writeFile does
async function play(label, share, { where = 'web', write = o => Promise.resolve({ uri: `file:///cache/${o.path}` }), bridge = 'real' } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  const call = d => { console.log(`share ${shown(d)}`); return share(d); };
  const filesystem = { writeFile: o => { console.log(`write ${o.directory} ${o.path}: ${Buffer.from(o.data, 'base64').toString()}`); return write(o); } };
  Object.defineProperty(global, 'navigator', {
    value: where === 'web' ? { share: call, canShare: () => true } : where === 'web-no' ? { share: call, canShare: () => false } : {},
    configurable: true });
  if (where.startsWith('app')) {
    const plugins = {};
    if (where !== 'app-no-share') plugins.Share = { share: call };
    if (where !== 'app-no-files') plugins.Filesystem = filesystem;
    globalThis.Capacitor = { isNativePlatform: () => true, Plugins: plugins };
  } else delete globalThis.Capacitor;
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    // an error the engine made carries a stack that names this machine's
    // paths and a message worded by this engine's version
    console.log(`hash: #${line.includes('"stack":') ? line.replace(/"stack":"[^"]*"/, '"stack":"(stack)"').replace(/,"message":"[^"]*"/, '') : line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

await play('the share sheet takes it', () => Promise.resolve());
await play('the user closes the share sheet: an AbortError', () => Promise.reject(named('AbortError', 'Share canceled by the user')));
await play('NotAllowedError: a failure the API documents', () => Promise.reject(named('NotAllowedError', 'no activation')));
await play('a rejection the API does not document: its own outcome, with the error',
  () => Promise.reject(clean(new Error('sharing is in progress'))));
await play('a rejection with nothing', () => Promise.reject());
await play('the share throws as it is called: its own outcome, with the error',
  () => { throw clean(new Error('threw')); });
await play('the share throws nothing', () => { throw undefined; });
await play('the browser cannot share the file', () => Promise.resolve(), { where: 'web-no' });
await play('the app: written to the cache and shared', () => Promise.resolve({ activityType: '' }), { where: 'app' });
await play('the app: the Share plugin says "Share canceled"', () => Promise.reject(clean(new Error('Share canceled'))), { where: 'app' });
await play('the app: the Share plugin rejects otherwise',
  () => Promise.reject(clean(new Error("Can't share while sharing is in progress"))), { where: 'app' });
await play('the app: the Share plugin throws as it is called',
  () => { throw clean(new Error('threw')); }, { where: 'app' });
await play('the app: the write to the cache rejects: its own outcome, with the error',
  () => Promise.resolve(), { where: 'app', write: () => Promise.reject(clean(new Error('disk full'))) });
await play('the app: the write to the cache rejects with nothing',
  () => Promise.resolve(), { where: 'app', write: () => Promise.reject() });
await play('the app: the write to the cache throws as it is called',
  () => Promise.resolve(), { where: 'app', write: () => { throw clean(new Error('threw')); } });
await play('the app: the write to the cache answers nothing: reading the answer threw',
  () => Promise.resolve(), { where: 'app', write: () => Promise.resolve() });
await play('the app has no Share plugin', () => Promise.resolve(), { where: 'app-no-share' });
await play('the app has no Filesystem plugin', () => Promise.resolve(), { where: 'app-no-files' });
await play('there is no way to share here', () => Promise.resolve(), { where: 'none' });
await play('the bytes fail to read: a thrown share', () => Promise.resolve(), { bridge: 'unreadable' });
await play('a code the bridge never gives is FileAnswerUnexpected',
  () => Promise.resolve(), { where: 'app', write: () => Promise.reject(clean(new Error('x'))), bridge: 'unexpected' });
console.log('done');
