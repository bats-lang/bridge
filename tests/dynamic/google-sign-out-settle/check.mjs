// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, as a browser page (no Capacitor) with Google Identity Services
// played: the app gets a token, signs out with google_sign_out_answer and
// then, with a second token, with the old google_sign_out. Each case plays
// the revoke differently: answered successful, answered unsuccessful,
// answered with no flag, a throwing answer, a revoke that throws, an answer
// whose flag throws when read (the old form says signed out, as the old JS
// never read the answer); and a reader who closes the window (no
// token, nothing to revoke), the app (no way here), the sign-in script not
// loading and a code the bridge never gives. Prints each revoke made and
// what the app says: the outcome of google_sign_out_answer (every
// constructor) and of the old google_sign_out, which says only signed out
// or failed (bridge#186, bridge#231).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-google-sign-out-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with the sign-in script failing to load where
// sign-out waits for it (once a token was given the script is there, so
// the app cannot reach this otherwise), and with a code it never gives (-9)
// where the answer with no flag had -5, to pass SignOutLoadFailed and
// SignOutUnexpected through the app
const loadMissing = "Promise.resolve().then(() => googleLoad().then(\n      () => new Promise(ok => view.google";
if (head.split(loadMissing).length !== 2) throw new Error('bridge.js: the sign-out load not found once');
const oddCode = 'googleSaid(id, r, -5)';
if (!head.includes(oddCode)) throw new Error('bridge.js: the odd answer case not found');
const loads = {
  real: await load('real', head),
  missing: await load('missing', head.replace(loadMissing,
    "Promise.resolve().then(() => Promise.reject((e => { delete e.stack; return e; })(new Error('Google sign-in did not load'))).then(\n      () => new Promise(ok => view.google")),
  unexpected: await load('unexpected', head.replace(oddCode, 'googleSaid(id, r, -9)')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

async function play(label, revoke, { closed = false, native = false, bridge = 'real' } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  globalThis.Capacitor = native ? { isNativePlatform: () => true, Plugins: {} } : undefined;
  let tokens = 0;
  win.google = {
    accounts: {
      oauth2: {
        initTokenClient: o => ({
          requestAccessToken: () => setTimeout(() => closed
            ? o.error_callback({ type: 'popup_closed' })
            : o.callback({ access_token: `token-${++tokens}` }), 5),
        }),
        revoke: (token, done) => { console.log(`revoke: ${token}`); return revoke(done); },
      },
    },
  };
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

await play('Google revokes the token',
  done => done({ successful: true }));
await play('Google answers that the revoke was not successful: its own outcome, with the answer',
  done => done({ successful: false, error: 'invalid_token', error_description: 'not a token' }));
await play('Google answers with no flag',
  done => done({ error: 'x' }));
await play('Google answers nothing',
  done => done());
await play('Google answers with something that is no object',
  done => done('revoked'));
await play('the revoke throws as it is called',
  () => { throw clean(new Error('threw')); });
await play('the answer has a throwing flag',
  done => done({ get successful() { throw clean(new Error('getter threw')); } }));
await play('the answer has a flag that throws nothing',
  done => done({ get successful() { throw undefined; } }));
await play('the reader closed the window: no token, nothing to revoke',
  done => done({ successful: true }), { closed: true });
await play('the app: no way to revoke here',
  done => done({ successful: true }), { native: true });
await play('the sign-in script does not load: its own outcome, with the error',
  done => done({ successful: true }), { bridge: 'missing' });
await play('a code the bridge never gives is SignOutUnexpected',
  done => done({ error: 'x' }), { bridge: 'unexpected' });
console.log('done');
