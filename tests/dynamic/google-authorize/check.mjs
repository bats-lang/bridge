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

const failure = (code, message) => Object.assign(new Error(message || code || 'failed'), code ? { code } : {});
// The statuses a refusal can carry, but NETWORK_ERROR and CANCELED (in
// silent, below), INTERNAL_ERROR (the clear stub) and DEVELOPER_ERROR (the
// prompting answers)
const STATUSES = ['SERVICE_VERSION_UPDATE_REQUIRED', 'SERVICE_DISABLED', 'SIGN_IN_REQUIRED', 'INVALID_ACCOUNT',
  'RESOLUTION_REQUIRED', 'ERROR', 'INTERRUPTED', 'TIMEOUT', 'API_NOT_CONNECTED', 'DEAD_CLIENT', 'REMOTE_EXCEPTION',
  'CONNECTION_SUSPENDED_DURING_CALL', 'RECONNECTION_TIMED_OUT_DURING_UPDATE', 'RECONNECTION_TIMED_OUT'];
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
  // platform's status; a rejection with no code; the plugin's
  // UNEXPECTED; a code nothing documents; CONSENT_SHOWING, which it never
  // answers; Play services' CANCELED (a refusal here)
  const silent = [
    () => Promise.resolve(authorization('token-1', ['scope-a', 'scope-b'], 'reader@example.com')),
    () => Promise.resolve({ authorization: null }),
    () => Promise.reject(failure('NETWORK_ERROR', '7: offline')),
    () => Promise.reject(failure()),
    () => Promise.reject(failure('UNEXPECTED', 'IllegalStateException: odd')),
    () => Promise.reject(failure('SOMETHING_NEW', 'new in Play services')),
    () => Promise.reject(failure('CONSENT_SHOWING', "Another call's consent screen is showing")),
    () => Promise.reject(failure('CANCELED', '16: canceled')),
    // the STATUSES, then SUCCESS and SUCCESS_CACHE, which are no refusal
    ...STATUSES.map(code => () => Promise.reject(failure(code, `${code} from Play services`))),
    () => Promise.reject(failure('SUCCESS', '0: ')),
    () => Promise.reject(failure('SUCCESS_CACHE', '-1: ')),
    // answers JS cannot pass on: no authorization object (an empty
    // answer, null, an authorization that is true); an access token
    // missing, not a string, or not printable ASCII; scopes that are
    // not a list, an empty list, or a list holding a scope that is not a
    // string, not printable ASCII, or a hole; an account that is not a
    // string, not printable ASCII, or missing
    () => Promise.resolve({}),
    () => Promise.resolve(null),
    () => Promise.resolve({ authorization: true }),
    () => Promise.resolve({ authorization: { grantedScopes: ['scope-a'], account: null } }),
    () => Promise.resolve(authorization(42, ['scope-a'], null)),
    () => Promise.resolve(authorization('tok en', ['scope-a'], null)),
    () => Promise.resolve(authorization('token-4', 'scope-a', null)),
    () => Promise.resolve(authorization('token-4', [], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 42], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 'scope b'], null)),
    () => Promise.resolve(authorization('token-4', new Array(1), null)),
    () => Promise.resolve(authorization('token-4', ['scope-a'], 42)),
    () => Promise.resolve(authorization('token-4', ['scope-a'], 'r\u00fc@x')),
    () => Promise.resolve({ authorization: { accessToken: 'token-4', grantedScopes: ['scope-a'] } }),
    // a status with an empty message: no message kept
    () => Promise.reject(Object.assign(new Error(''), { code: 'NETWORK_ERROR' })),
    // rejections that are not an object whose code and message are each
    // text or absent: no value, a string, null, an error whose code is a
    // number and one whose message is a number
    () => Promise.reject(),
    () => Promise.reject('refused as a string'),
    () => Promise.reject(null),
    () => Promise.reject(Object.assign(new Error('7: offline'), { code: 7 })),
    () => Promise.reject(Object.assign(new Error(''), { code: 'NETWORK_ERROR', message: 7 })),
    // rejections that are taken: an object with no code and no message
    // (unexpected, with bridge's message naming that), an error whose
    // code is null and one whose message is null
    () => Promise.reject({}),
    () => Promise.reject(Object.assign(new Error('m'), { code: null })),
    () => Promise.reject(Object.assign(new Error(''), { code: 'NETWORK_ERROR', message: null })),
  ];
  // authorizeScopes: granted with no account; the plugin's CANCELED;
  // another consent screen showing; no authorization, which the plugin
  // never answers; Play services' DEVELOPER_ERROR; Play services' own
  // CANCELED status (16); a grant whose scopes are not a list; the
  // plugin's UNEXPECTED, a rejection with no code, a code nothing
  // documents
  const prompting = [
    () => Promise.resolve(authorization('token-2', ['scope-a', 'scope-c'], null)),
    () => Promise.reject(failure('CANCELED', 'The reader backed out of the consent screen')),
    () => Promise.reject(failure('CONSENT_SHOWING')),
    () => Promise.resolve({ authorization: null }),
    () => Promise.reject(failure('DEVELOPER_ERROR', '10: ')),
    () => Promise.reject(failure('CANCELED', '16: ')),
    () => Promise.resolve({ authorization: { accessToken: 'token-3', grantedScopes: 'scope-a', account: null } }),
    // what the plugin answers UNEXPECTED, a rejection with no code, and a
    // code nothing documents
    () => Promise.reject(failure('UNEXPECTED', 'The consent screen completed but returned nothing')),
    () => Promise.reject(failure(null, 'no code given')),
    () => Promise.reject(failure('SOMETHING_NEW', 'new in Play services')),
  ];
  if (native) globalThis.Capacitor = {
    isNativePlatform: () => true,
    Plugins: {
      GoogleAuthorize: {
        authorizationForScopes: o => { console.log(`authorizationForScopes: ${JSON.stringify(o)}`); return silent.shift()(); },
        authorizeScopes: o => { console.log(`authorizeScopes: ${JSON.stringify(o)}`); return prompting.shift()(); },
        clearAuthorizationToken: o => {
          console.log(`clearAuthorizationToken: ${JSON.stringify(o)}`);
          if (o.accessToken === 'refused-token') return Promise.reject(failure('INTERNAL_ERROR', '8: failed'));
          if (o.accessToken === 'odd-token') return Promise.reject(failure('UNEXPECTED', 'NullPointerException: null'));
          if (o.accessToken === 'showing-token') return Promise.reject(failure('CONSENT_SHOWING', 'not documented here'));
          // a status with an empty message: no message kept
          if (o.accessToken === 'quiet-token') return Promise.reject(Object.assign(new Error(''), { code: 'INTERNAL_ERROR' }));
          // a rejection that is not an error: unexpected, no code, JS's message
          if (o.accessToken === 'string-token') return Promise.reject('refused as a string');
          // an error whose message is a number: unexpected, no code, JS's message
          if (o.accessToken === 'number-token') return Promise.reject(Object.assign(new Error(''), { code: 'INTERNAL_ERROR', message: 8 }));
          return Promise.resolve();
        },
        revokeAccess: o => {
          console.log(`revokeAccess: ${JSON.stringify(o)}`);
          if (o.account === 'refused@example.com') return Promise.reject(failure('NETWORK_ERROR', '7: offline'));
          if (o.account === 'odd@example.com') return Promise.reject(failure('UNEXPECTED', 'IllegalStateException: odd'));
          if (o.account === 'showing@example.com') return Promise.reject(failure('CONSENT_SHOWING', 'not documented here'));
          // a rejection with no value: unexpected, no code, JS's message
          if (o.account === 'silent@example.com') return Promise.reject();
          // null: unexpected, no code, JS's message
          if (o.account === 'null@example.com') return Promise.reject(null);
          return Promise.resolve();
        },
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
