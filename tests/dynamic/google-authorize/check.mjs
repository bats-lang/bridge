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
// The statuses CommonStatusCodes names (play-services-basement 18.9.0) that
// a refusal can carry, but NETWORK_ERROR and CANCELED (answers in silent,
// below, before the map of these), INTERNAL_ERROR (the clear stub) and DEVELOPER_ERROR (the
// prompting answers): 14
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
    // the 14 STATUSES, then SUCCESS, which is no refusal
    ...STATUSES.map(code => () => Promise.reject(failure(code, `${code} from Play services`))),
    () => Promise.reject(failure('SUCCESS', '0: ')),
    // answers the plugin does not document, and grants it passes on
    // that bridge does not take (app.bats, above s7d, says which is which)
    () => Promise.resolve({}),
    () => Promise.resolve(null),
    () => Promise.resolve(authorization('   ', ['scope-a'], null)),
    () => Promise.resolve(authorization('token-4', [], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a'], '')),
    () => Promise.resolve(authorization('token-4', ['scope-a'], 42)),
    () => Promise.resolve(authorization('token-4', ['scope-a'], '  ')),
    () => Promise.resolve(authorization('token-4', ['scope-a', 'scope b'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 42], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', '   '], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', ''], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 'a"b'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 'a\\b'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 'caf\u00e9'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 'scope\u0001a'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a', 'scope\u007fa'], null)),
    () => Promise.resolve({ authorization: { grantedScopes: ['scope-a'], account: null } }),
    () => Promise.resolve(authorization(42, ['scope-a'], null)),
    () => Promise.resolve(authorization('\u00e9\u00e9', ['scope-a'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a'], '\u00fc\u00fc')),
    () => Promise.resolve({ authorization: { accessToken: 'token-4', grantedScopes: ['scope-a'] } }),
    () => Promise.resolve(authorization('t'.repeat(5000), ['scope-a'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a'], 'a'.repeat(5000))),
    () => Promise.resolve(authorization('tok\ud800', ['scope-a'], null)),
    () => Promise.resolve(authorization('token-4', ['scope-a'], 'r\udc00@x')),
    // a status with an empty message: no message kept
    () => Promise.reject(Object.assign(new Error(''), { code: 'NETWORK_ERROR' })),
    // a rejection that is not an error whose code and message are text:
    // one with no value, a string, and an error whose code is a number
    () => Promise.reject(),
    () => Promise.reject('refused as a string'),
    () => Promise.reject(Object.assign(new Error('7: offline'), { code: 7 })),
    // and an error whose message is a number, null, an error whose
    // message holds a lone surrogate, and an error with no code and no
    // message (kept as none and none)
    () => Promise.reject(Object.assign(new Error(''), { code: 'NETWORK_ERROR', message: 7 })),
    () => Promise.reject(null),
    () => Promise.reject(Object.assign(new Error('m\ud800'), { code: 'NETWORK_ERROR' })),
    () => Promise.reject({}),
    // an authorization that is not an object; a token and an account
    // starting with a byte order mark; a token and an account of exactly
    // 4096 bytes, taken (then cleared, and the account's grant revoked),
    // and of 4097 bytes in 2049 UTF-16 units; an account holding a letter
    // outside ASCII, taken and revoked as it came; a scope holding each
    // end of NQCHAR's ranges, taken
    () => Promise.resolve({ authorization: true }),
    () => Promise.resolve(authorization('\ufefftoken-6', ['scope-a'], null)),
    () => Promise.resolve(authorization('token-6', ['scope-a'], '\ufeffr@x')),
    () => Promise.resolve(authorization('t'.repeat(4096), ['scope-a'], null)),
    () => Promise.resolve(authorization('a' + '\u00e9'.repeat(2048), ['scope-a'], null)),
    () => Promise.resolve(authorization('token-7', ['scope-a'], 'a'.repeat(4096))),
    () => Promise.resolve(authorization('token-7', ['scope-a'], 'a' + '\u00e9'.repeat(2048))),
    () => Promise.resolve(authorization('token-8', ['scope-a'], 'r\u00fc@x')),
    () => Promise.resolve(authorization('token-9', ['!#[]~'], null)),
    // blank as Java has it: a token of each end of googleBlank's ranges,
    // empty or blank; then a token of each character just outside them
    // (the no-break spaces among them), not blank and holding no visible
    // ASCII character
    () => Promise.resolve(authorization('\t\r\x1c\x20\u1680\u2000\u2006\u2008\u200a\u2028\u2029\u205f\u3000', ['scope-a'], null)),
    ...['\x08', '\x0e', '\x1b', '\u00a0', '\u167f', '\u1681', '\u1fff', '\u2007', '\u200b', '\u2027', '\u202a', '\u202f', '\u205e',
      '\u2060', '\u2fff', '\u3001'].map(t => () => Promise.resolve(authorization(t, ['scope-a'], null))),
    // a token of only an exclamation mark and an account of only a tilde,
    // and a token holding a surrogate pair and a byte order mark that
    // does not lead, each taken (cleared and revoked as they came); a
    // token of only DEL and one of a space and a letter outside ASCII,
    // holding no visible ASCII character; granted scopes with a hole
    () => Promise.resolve(authorization('!', ['scope-a'], '~')),
    () => Promise.resolve(authorization('tok\u{1f600}\ufeff', ['scope-a'], null)),
    () => Promise.resolve(authorization('\x7f', ['scope-a'], null)),
    () => Promise.resolve(authorization(' \u00e9', ['scope-a'], null)),
    () => Promise.resolve(authorization('token-4', new Array(1), null)),
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
  // what a clear or a revoke is given, a text over 100 characters by its
  // length alone
  const given = o => JSON.stringify(o, (k, v) => typeof v === 'string' && v.length > 100 ? `${v.length} characters` : v);
  if (native) globalThis.Capacitor = {
    isNativePlatform: () => true,
    Plugins: {
      GoogleAuthorize: {
        authorizationForScopes: o => { console.log(`authorizationForScopes: ${JSON.stringify(o)}`); return silent.shift()(); },
        authorizeScopes: o => { console.log(`authorizeScopes: ${JSON.stringify(o)}`); return prompting.shift()(); },
        clearAuthorizationToken: o => {
          console.log(`clearAuthorizationToken: ${given(o)}`);
          if (o.accessToken === 'refused-token') return Promise.reject(failure('INTERNAL_ERROR', '8: failed'));
          if (o.accessToken === 'odd-token') return Promise.reject(failure('UNEXPECTED', 'NullPointerException: null'));
          if (o.accessToken === 'showing-token') return Promise.reject(failure('CONSENT_SHOWING', 'not documented here'));
          // a status with an empty message: no message kept
          if (o.accessToken === 'quiet-token') return Promise.reject(Object.assign(new Error(''), { code: 'INTERNAL_ERROR' }));
          // a rejection that is not an error: said to be so
          if (o.accessToken === 'string-token') return Promise.reject('refused as a string');
          // an error whose code holds a lone surrogate: said to be no text
          if (o.accessToken === 'surrogate-token') return Promise.reject(Object.assign(new Error('8: failed'), { code: 'INTERNAL_ERROR\udc00' }));
          // an error whose message is a number: said to be so
          if (o.accessToken === 'number-token') return Promise.reject(Object.assign(new Error(''), { code: 'INTERNAL_ERROR', message: 8 }));
          return Promise.resolve();
        },
        revokeAccess: o => {
          console.log(`revokeAccess: ${given(o)}`);
          if (o.account === 'refused@example.com') return Promise.reject(failure('NETWORK_ERROR', '7: offline'));
          if (o.account === 'odd@example.com') return Promise.reject(failure('UNEXPECTED', 'IllegalStateException: odd'));
          if (o.account === 'showing@example.com') return Promise.reject(failure('CONSENT_SHOWING', 'not documented here'));
          // a rejection with no value: said to be no error
          if (o.account === 'silent@example.com') return Promise.reject();
          // null: said to be no error
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
