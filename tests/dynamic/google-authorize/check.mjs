// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, twice: playing the native app with the GoogleAuthorize plugin
// (bats-lang/capacitor-plugins' google-authorize), whose answers come in
// the order the app asks, and a browser (no Capacitor). The plugin prints
// each call with what it was given; each hash the app sets is printed.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const settle = () => new Promise(r => setTimeout(r, 300));
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
// bridge.js boots itself at its end; keep only loadWASM
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');

const failure = code => Object.assign(new Error(code || 'failed'), code ? { code } : {});
const authorization = (accessToken, grantedScopes, account) => ({ authorization: { accessToken, grantedScopes, account } });

async function run(label, native) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  // authorizationForScopes: granted with an account; consent needed; the
  // platform's code; a rejection with no code
  const silent = [
    () => Promise.resolve(authorization('token-1', ['scope-a', 'scope-b'], 'reader@example.com')),
    () => Promise.resolve({ authorization: null }),
    () => Promise.reject(failure('NETWORK_ERROR')),
    () => Promise.reject(failure()),
  ];
  // authorizeScopes: granted with no account; canceled; another consent
  // screen showing; no authorization, which the plugin never answers
  const prompting = [
    () => Promise.resolve(authorization('token-2', ['scope-a', 'scope-c'], null)),
    () => Promise.reject(failure('CANCELED')),
    () => Promise.reject(failure('CONSENT_SHOWING')),
    () => Promise.resolve({ authorization: null }),
  ];
  if (native) globalThis.Capacitor = {
    isNativePlatform: () => true,
    Plugins: {
      GoogleAuthorize: {
        authorizationForScopes: o => { console.log(`authorizationForScopes: ${JSON.stringify(o)}`); return silent.shift()(); },
        authorizeScopes: o => { console.log(`authorizeScopes: ${JSON.stringify(o)}`); return prompting.shift()(); },
        clearAuthorizationToken: o => {
          console.log(`clearAuthorizationToken: ${JSON.stringify(o)}`);
          return o.accessToken === 'refused-token' ? Promise.reject(failure('INTERNAL_ERROR')) : Promise.resolve();
        },
        revokeAccess: o => { console.log(`revokeAccess: ${JSON.stringify(o)}`); return Promise.resolve(); },
      },
    },
  };
  else delete globalThis.Capacitor;
  win.addEventListener('hashchange', e => console.log(`hash: ${decodeURIComponent(new URL(e.newURL).hash)}`));
  const tmp = join(tmpdir(), `bridge-google-authorize-${process.pid}-${native ? 'app' : 'browser'}.mjs`);
  writeFileSync(tmp, src.slice(0, boot) + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});
  await settle();
}

await run('app', true);
await run('browser page', false);
