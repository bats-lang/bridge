// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, as a browser page (no Capacitor) with Google Identity Services
// played: the app asks for a token with google_token_get_answer and then,
// asking again, with the old google_token_get. Each case plays Google
// differently: a token, the reader closing the window or refusing, Google
// answering with no token (an error, nothing), a window that does not open,
// a client that throws as it is made or asked, an answer whose token cannot
// be read or written down (a getter that throws, a symbol), and the app (no
// way here), the sign-in script not loading and a code the bridge never
// gives. Prints what the app says: the outcome of google_token_get_answer
// (every constructor) and of the old google_token_get, which says only
// token, canceled, refused or unavailable (bridge#186, bridge#235).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-google-token-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with the sign-in script failing to load where the
// request waits for it (once it was asked about the script is there, so the
// app cannot reach this otherwise), and with a code it never gives (-9)
// where Google's answer with no token had -3, to pass TokenLoadFailed and
// TokenUnexpected through the app
const loadWaits = "Promise.resolve().then(() => googleLoad().then(\n      () => new Promise(ok => {";
if (head.split(loadWaits).length !== 2) throw new Error('bridge.js: the token request load not found once');
const refusedCode = 'googleSaid(id, r, -3)';
if (head.split(refusedCode).length !== 2) throw new Error('bridge.js: the refused answer case not found once');
const loads = {
  real: await load('real', head),
  missing: await load('missing', head.replace(loadWaits,
    "Promise.resolve().then(() => Promise.reject((e => { delete e.stack; return e; })(new Error('Google sign-in did not load'))).then(\n      () => new Promise(ok => {")),
  unexpected: await load('unexpected', head.replace(refusedCode, 'googleSaid(id, r, -9)')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

// Google's window for one request: given the options of initTokenClient, it
// answers by calling its callback or its error_callback
const answers = (answer) => o => ({ requestAccessToken: () => setTimeout(() => answer(o), 5) });

async function play(label, client, { native = false, bridge = 'real' } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  globalThis.Capacitor = native ? { isNativePlatform: () => true, Plugins: {} } : undefined;
  let requests = 0;
  win.google = { accounts: { oauth2: { initTokenClient: o => { requests += 1; return client(o, requests); } } } };
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

await play('Google gives a token',
  answers(o => o.callback({ access_token: 'token-1' })));
await play('the reader closes the window',
  answers(o => o.error_callback({ type: 'popup_closed' })));
await play('the reader refuses access',
  answers(o => o.callback({ error: 'access_denied' })));
await play('Google answers with an error and no token: its own outcome, with the answer',
  answers(o => o.callback({ error: 'invalid_client', error_description: 'not registered' })));
await play('Google answers with nothing',
  answers(o => o.callback()));
await play('Google answers with a token that is empty',
  answers(o => o.callback({ access_token: '', error: 'x' })));
await play('the window does not open: Google tells with an error of its own',
  answers(o => o.error_callback({ type: 'popup_failed_to_open', message: 'blocked' })));
await play('Google tells with an error that is no object',
  answers(o => o.error_callback('blocked')));
await play('the client throws as it is made',
  () => { throw clean(new Error('made')); });
await play('the client throws as it is asked',
  () => ({ requestAccessToken: () => { throw clean(new Error('asked')); } }));
await play('the answer has a token that throws when read',
  answers(o => o.callback({ get access_token() { throw clean(new Error('getter threw')); } })));
await play('the answer has a token that throws nothing when read',
  answers(o => o.callback({ get access_token() { throw undefined; } })));
await play('the answer has a token that cannot be written down',
  answers(o => o.callback({ access_token: Symbol('token') })));
await play('the error has a type that throws when read',
  answers(o => o.error_callback({ get type() { throw clean(new Error('type threw')); } })));
await play('the app: no way to ask here',
  answers(o => o.callback({ access_token: 'token-1' })), { native: true });
await play('the sign-in script does not load: its own outcome, with the error',
  answers(o => o.callback({ access_token: 'token-1' })), { bridge: 'missing' });
await play('a code the bridge never gives is TokenUnexpected',
  answers(o => o.callback({ error: 'x' })), { bridge: 'unexpected' });
console.log('done');
