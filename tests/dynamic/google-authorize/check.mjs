// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, twice: playing the native app with the GoogleAuthorize plugin
// (bats-lang/capacitor-plugins' google-authorize), whose answers come in
// the order the app asks, and a browser (no Capacitor). The plugin prints
// each call with what it was given; each hash the app sets is printed.
//
// The answers are the plugin's documented ones, a fixed list of nasty
// ones (values JSON has no form for, throwing getters and Proxy traps,
// cycles, huge and odd strings, thenables, answers just under and over
// the 1 MiB cap), answers bridge's JS never gives (put in as they reach
// the app), and a fuzz of random values from a fixed seed. Then it
// checks that every call settled exactly once with a known outcome, and
// that every unexpected one carries a non-empty text.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
// bridge.js boots itself at its end; keep only loadWASM
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');

// The counts the app asks in (app.bats' SILENT, PROMPTING, CLEARS, REVOKES)
const COUNTS = { authorizationForScopes: 400, authorizeScopes: 80, clearAuthorizationToken: 80, revokeAccess: 80 };
const CAP = 1048576;
// An error the engine throws (a revoked Proxy's) has a stack with no
// frames, so its text holds no paths, whose length varies with the
// process id
Error.stackTraceLimit = 0;

// A random number generator from a fixed seed (mulberry32)
function random(seed) {
  return () => {
    seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// An Error whose stack is fixed, so the output holds no paths
function error(message, fields = {}, Kind = Error) {
  const e = new Kind(message);
  Object.defineProperty(e, 'stack', { value: `${Kind.name}: ${message}\n    at the plugin`, writable: true, configurable: true });
  return Object.assign(e, fields);
}
class PluginError extends Error {}
const failure = (code, message) => error(message ?? code ?? 'failed', code === undefined ? {} : { code });
const authorization = (accessToken, grantedScopes, account) => ({ authorization: { accessToken, grantedScopes, account } });
const thrower = name => { throw error(`${name} threw`); };
const getters = (object, names) => {
  for (const name of names) Object.defineProperty(object, name, { enumerable: true, get: () => thrower(name) });
  return object;
};
const hostile = () => new Proxy({}, {
  get: () => thrower('get'), ownKeys: () => thrower('ownKeys'), has: () => thrower('has'),
  getPrototypeOf: () => thrower('getPrototypeOf'), getOwnPropertyDescriptor: () => thrower('getOwnPropertyDescriptor'),
});
const revoked = () => { const r = Proxy.revocable({}, {}); r.revoke(); return r.proxy; };
const cyclic = () => { const o = { name: 'cycle' }; o.self = o; return o; };
// Arrays nested depth deep: json reads 512 levels, and refuses more
const nested = depth => { let v = []; for (let i = 1; i < depth; i++) v = [v]; return v; };
// A valid authorization padded with a field so its JSON is length bytes
function padded(length) {
  const answer = { authorization: { accessToken: 'token-pad', grantedScopes: ['scope-a'], account: null }, pad: '' };
  answer.pad = 'p'.repeat(length - JSON.stringify(answer).length);
  if (JSON.stringify(answer).length !== length) throw new Error('padded: wrong length');
  return answer;
}

// Odd strings: non-ASCII, lone surrogates, controls, quotes, huge
const STRINGS = ['', 'plain', 'tökén', '\ud800', '\udc00x', 'a\u0000b', 'tab\there', 'quote"back\\slash', ' ', 'x'.repeat(5000)];

// A random value of depth at most depth
function value(next, depth) {
  const pick = Math.floor(next() * (depth > 0 ? 22 : 14));
  switch (pick) {
    case 0: return null;
    case 1: return undefined;
    case 2: return Math.floor(next() * 2000) - 1000;
    case 3: return next() * 10;
    case 4: return [NaN, Infinity, -Infinity, -0][Math.floor(next() * 4)];
    case 5: return BigInt(Math.floor(next() * 100000));
    case 6: return Symbol(`s${Math.floor(next() * 10)}`);
    case 7: return STRINGS[Math.floor(next() * STRINGS.length)];
    case 8: return next() < 0.5;
    case 9: return () => 1;
    case 10: return ['token-r', 'scope-a', 'NETWORK_ERROR', 'CANCELED', 'UNIMPLEMENTED', 'CONSENT_SHOWING'][Math.floor(next() * 6)];
    case 11: return hostile();
    case 12: return revoked();
    case 13: return new Date(0);
    case 14: return [value(next, depth - 1), value(next, depth - 1)];
    case 15: return { code: value(next, depth - 1), message: value(next, depth - 1) };
    case 16: return error(STRINGS[Math.floor(next() * STRINGS.length)], { code: value(next, depth - 1) });
    case 17: return { authorization: value(next, depth - 1) };
    case 18: return authorization(value(next, depth - 1), value(next, depth - 1), value(next, depth - 1));
    case 19: return getters({}, ['code', 'message', 'authorization'].filter(() => next() < 0.5));
    case 20: return Object.freeze({ authorization: { accessToken: 'token-f', grantedScopes: ['scope-a'], account: value(next, depth - 1) } });
    default: return cyclic();
  }
}
// A random answer: resolved or rejected with a random value
const fuzz = next => {
  const v = value(next, 3);
  return next() < 0.5 ? () => Promise.resolve(v) : () => Promise.reject(v);
};
const fill = (list, count, next) => {
  if (list.length >= count) throw new Error(`${list.length} answers for ${count} calls`);
  while (list.length < count) list.push(fuzz(next));
  return list;
};

// Answers bridge's JS never gives, put in as they reach the app: an
// answer code in place of the next one, and the next text withheld; and
// the plugin's lookup throwing as the next call of the same method
// begins (its queued answer is then never asked for, and skipped)
let oddAnswer = null;
let textWithheld = false;
let lookupThrow = null;
const skipped = { authorizationForScopes: 0, authorizeScopes: 0, clearAuthorizationToken: 0, revokeAccess: 0 };
const instantiate = WebAssembly.instantiate;
WebAssembly.instantiate = async (bytes, imports) => {
  const text = imports.env.bats_js_google_authorize_text;
  imports.env.bats_js_google_authorize_text = id => {
    const h = text(id);
    if (textWithheld) { textWithheld = false; return 0; }
    return h;
  };
  const result = await instantiate(bytes, imports);
  const exports = { ...result.instance.exports };
  const answer = exports.bats_on_permission_result;
  exports.bats_on_permission_result = (id, v) => {
    if (oddAnswer !== null) { v = oddAnswer; oddAnswer = null; }
    return answer(id, v);
  };
  return { module: result.module, instance: { exports } };
};
const oddly = (code, f) => () => { oddAnswer = code; return f(); };
const withheld = (code, f) => () => { oddAnswer = code; textWithheld = true; return f(); };
const SKIPPED = () => Promise.reject(error('never asked for'));
const lookupThrows = thrown => [method => { lookupThrow = { thrown, method }; return Promise.resolve(); }, SKIPPED];

// The rejections every method is played with
const rejections = () => [
  () => Promise.reject(failure('UNEXPECTED', 'IllegalStateException: odd')),
  () => Promise.reject(failure('SOMETHING_NEW', 'new in Play services')),
  () => Promise.reject(failure('', 'an empty code')),
  () => Promise.reject(failure(null, 'a null code')),
  () => Promise.reject(failure(undefined, 'no code')),
  () => Promise.reject(failure('UNIMPLEMENTED', 'Not implemented on this platform')),
  () => Promise.reject(failure('CONSENT_SHOWING', "Another call's consent screen is showing")),
  () => Promise.reject(error('subclassed', { code: 'NETWORK_ERROR', extra: { n: 1 } }, PluginError)),
  () => Promise.reject(failure('NETWORK_ERROR', 'x'.repeat(5000))),
  () => Promise.reject(failure('NETWORK_ERROR', '\ud800 lone')),
  () => Promise.reject(failure('NÉTWORK', 'not ASCII')),
  () => Promise.reject(Object.assign(error('7: offline'), { code: 7 })),
  () => Promise.reject(Object.assign(error(''), { code: 'NETWORK_ERROR', message: 7 })),
  () => Promise.reject({ code: 7, message: 8 }),
  () => Promise.reject({ code: 12n }),
  () => Promise.reject({}),
  () => Promise.reject(),
  () => Promise.reject(null),
  () => Promise.reject(42),
  () => Promise.reject(NaN),
  () => Promise.reject(Symbol('rejected')),
  () => Promise.reject(7n),
  () => Promise.reject('refused as a string'),
  () => Promise.reject(''),
  () => Promise.reject(getters(error('getters'), ['code'])),
  () => Promise.reject(getters({}, ['message'])),
  () => Promise.reject(hostile()),
  () => Promise.reject(revoked()),
  () => Promise.reject(Object.assign(cyclic(), { code: 'NETWORK_ERROR' })),
  () => Promise.reject(Object.freeze(failure('INTERNAL_ERROR', '8: frozen'))),
  () => Promise.reject(Object.assign(Object.create(null), { code: 'TIMEOUT', message: 'no prototype' })),
  () => Promise.reject({ toJSON() { throw error('toJSON threw'); } }),
  () => Promise.reject(nested(512)),
  () => Promise.reject({ code: 'NETWORK_ERROR', message: nested(513) }),
  () => Promise.reject({ code: 'NETWORK_ERROR', message: 'x'.repeat(CAP) }),
  () => { throw error('the method threw'); },
  ...lookupThrows(error('the lookup threw')),
  ...lookupThrows(cyclic()),
  ...lookupThrows(hostile()),
  oddly(7, () => Promise.reject(failure('NETWORK_ERROR', '7: offline'))),
  oddly(12, () => Promise.reject(failure('NETWORK_ERROR', '7: offline'))),
  oddly(44, () => Promise.reject(failure('NETWORK_ERROR', '7: offline'))),
  oddly(0, () => Promise.reject(failure('NETWORK_ERROR', '7: offline'))),
  withheld(-1, () => Promise.reject(failure('NETWORK_ERROR', '7: offline'))),
];

// Each status CommonStatusCodes names, and SUCCESS and SUCCESS_CACHE
const STATUSES = ['SERVICE_VERSION_UPDATE_REQUIRED', 'SERVICE_DISABLED', 'SIGN_IN_REQUIRED', 'INVALID_ACCOUNT',
  'RESOLUTION_REQUIRED', 'NETWORK_ERROR', 'INTERNAL_ERROR', 'DEVELOPER_ERROR', 'ERROR', 'INTERRUPTED', 'TIMEOUT',
  'CANCELED', 'API_NOT_CONNECTED', 'DEAD_CLIENT', 'REMOTE_EXCEPTION', 'CONNECTION_SUSPENDED_DURING_CALL',
  'RECONNECTION_TIMED_OUT_DURING_UPDATE', 'RECONNECTION_TIMED_OUT', 'SUCCESS', 'SUCCESS_CACHE'];

// authorizationForScopes: granted (the first, asked with drive.appdata
// twice); consent needed; the odd answers; each status; the rejections
const answers = () => [
  () => Promise.resolve(authorization('token-1', ['scope-a', 'scope-b'], 'reader@example.com')),
  () => Promise.resolve({ authorization: null }),
  () => Promise.resolve(authorization('token-2', ['scope-a'], null)),
  () => Promise.resolve({ authorization: { accessToken: 'token-3', grantedScopes: ['scope-a'], account: null, extra: 1.5 } }),
  () => Promise.resolve(Object.freeze(authorization('token-4', ['scope-a'], null))),
  () => Promise.resolve({ authorization: Object.assign(Object.create(null), { accessToken: 'token-5', grantedScopes: ['scope-a'], account: null }) }),
  () => Promise.resolve({ then: ok => ok(authorization('token-6', ['scope-a'], null)) }),
  () => Promise.resolve({ then: () => { throw error('then threw'); } }),
  () => Promise.resolve(padded(CAP)),
  () => Promise.resolve(padded(CAP + 1)),
  () => Promise.resolve(nested(512)),
  () => Promise.resolve(nested(513)),
  () => Promise.resolve({}),
  () => Promise.resolve(),
  () => Promise.resolve(null),
  () => Promise.resolve(0),
  () => Promise.resolve(NaN),
  () => Promise.resolve([authorization('token-x', ['scope-a'], null)]),
  () => Promise.resolve(Symbol('answer')),
  () => Promise.resolve(12n),
  () => Promise.resolve('text'),
  () => Promise.resolve(() => 1),
  () => Promise.resolve({ authorization: true }),
  () => Promise.resolve({ authorization: [] }),
  () => Promise.resolve({ authorization: {} }),
  () => Promise.resolve(authorization(42, ['scope-a'], null)),
  () => Promise.resolve(authorization('', ['scope-a'], null)),
  () => Promise.resolve(authorization('tok en', ['scope-a'], null)),
  () => Promise.resolve(authorization('töken', ['scope-a'], null)),
  () => Promise.resolve(authorization('\ud800', ['scope-a'], null)),
  () => Promise.resolve(authorization('t'.repeat(5000), ['scope-a'], null)),
  () => Promise.resolve(authorization('token-7', 'scope-a', null)),
  () => Promise.resolve(authorization('token-7', [], null)),
  () => Promise.resolve(authorization('token-7', [''], null)),
  () => Promise.resolve(authorization('token-7', ['scope-a', 42], null)),
  () => Promise.resolve(authorization('token-7', ['scope a'], null)),
  () => Promise.resolve(authorization('token-7', ['scöpe'], null)),
  () => Promise.resolve(authorization('token-7', new Array(1), null)),
  () => Promise.resolve(authorization('token-7', ['scope-a'], 42)),
  () => Promise.resolve(authorization('token-7', ['scope-a'], '')),
  () => Promise.resolve(authorization('token-7', ['scope-a'], 'rü@x')),
  () => Promise.resolve({ authorization: { accessToken: 'token-7', grantedScopes: ['scope-a'] } }),
  () => Promise.resolve(getters({}, ['authorization'])),
  () => Promise.resolve({ authorization: getters({}, ['accessToken']) }),
  () => Promise.resolve({ authorization: getters({ accessToken: 'token-8' }, ['grantedScopes']) }),
  () => Promise.resolve({ authorization: getters({ accessToken: 'token-8', grantedScopes: ['scope-a'] }, ['account']) }),
  () => Promise.resolve(hostile()),
  () => Promise.resolve({ authorization: hostile() }),
  () => Promise.resolve(revoked()),
  () => Promise.resolve(Object.assign(cyclic(), authorization('token-9', ['scope-a'], null))),
  oddly(7, () => Promise.resolve(authorization('token-odd', ['scope-a'], null))),
  withheld(1, () => Promise.resolve(authorization('token-odd', ['scope-a'], null))),
  ...STATUSES.map(code => () => Promise.reject(failure(code, `${code} from Play services`))),
  ...rejections(),
];

async function run(label, native) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  const next = random(334);
  const queues = {
    authorizationForScopes: fill(answers(), COUNTS.authorizationForScopes, next),
    authorizeScopes: fill([
      () => Promise.resolve(authorization('token-p', ['scope-a', 'scope-c'], null)),
      () => Promise.reject(failure('CANCELED', 'The reader backed out of the consent screen')),
      () => Promise.reject(failure('CANCELED', '16: ')),
      () => Promise.resolve({ authorization: null }),
      () => Promise.reject(failure('DEVELOPER_ERROR', '10: ')),
      ...rejections(),
    ], COUNTS.authorizeScopes, next),
    clearAuthorizationToken: fill([
      () => Promise.resolve(),
      () => Promise.resolve({ odd: 'resolved with something' }),
      () => Promise.resolve(hostile()),
      () => Promise.reject(failure('INTERNAL_ERROR', '8: failed')),
      ...rejections(),
    ], COUNTS.clearAuthorizationToken, next),
    revokeAccess: fill([
      () => Promise.resolve(),
      () => Promise.reject(failure('NETWORK_ERROR', '7: offline')),
      ...rejections(),
    ], COUNTS.revokeAccess, next),
  };
  const calls = { authorizationForScopes: 0, authorizeScopes: 0, clearAuthorizationToken: 0, revokeAccess: 0 };
  // The app's own calls take the next queued answer; a clear and a
  // revoke of what an authorization gave resolve
  const plugin = method => o => {
    console.log(`${method}: ${JSON.stringify(o)}`);
    const queued = method === 'clearAuthorizationToken' ? o.accessToken === 'queued-token'
      : method === 'revokeAccess' ? o.account === 'queued@example.com' : true;
    if (!queued) return Promise.resolve();
    calls[method]++;
    const f = queues[method].shift();
    if (!f) throw new Error(`${method}: no answer queued`);
    return f(method);
  };
  const plugins = { GoogleAuthorize: Object.fromEntries(Object.keys(COUNTS).map(m => [m, plugin(m)])) };
  if (native) globalThis.Capacitor = {
    isNativePlatform: () => true,
    get Plugins() {
      if (lookupThrow !== null) {
        const { thrown, method } = lookupThrow;
        lookupThrow = null;
        queues[method].shift();
        skipped[method]++;
        throw thrown;
      }
      return plugins;
    },
  };
  else delete globalThis.Capacitor;
  const lines = [];
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line;
    try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    lines.push(line);
    console.log(`hash: #${line}`);
  });
  const tmp = join(tmpdir(), `bridge-google-authorize-${process.pid}-${native ? 'app' : 'browser'}.mjs`);
  writeFileSync(tmp, src.slice(0, boot) + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});
  // until no hash has come for a second
  for (let count = -1; count !== lines.length; ) {
    count = lines.length;
    await new Promise(r => setTimeout(r, 1000));
  }
  check(label, native, lines, calls, queues);
}

// Every call settled once with a known outcome, and every unexpected
// one carries a non-empty text
const CALLS = ['authorization for scopes', 'authorize scopes', 'clear', 'revoke'];
const OUTCOMES = ['authorized', 'not authorized', 'canceled', 'consent showing', 'refused', 'unavailable', 'unexpected', 'changed'];
const CASES = ['answer not JSON', 'answer unparsed', 'answer too large', 'no authorization object', 'token not printable',
  'scopes not printable', 'account not printable', 'rejection not JSON', 'rejection unparsed', 'rejection too large',
  'rejection text', 'rejection not object', 'code not text', 'rejected other', 'decode threw', 'odd answer'];
function check(label, native, lines, calls, queues) {
  const text = lines.map(l => l.slice(6));
  const problems = [];
  let asked = 0, answered = 0;
  text.forEach((t, i) => {
    if (CALLS.includes(t)) {
      asked++;
      if (!OUTCOMES.includes(text[i + 1])) problems.push(`line ${i}: ${t} then ${text[i + 1]}`);
    }
    // the first line says whether the plugin is there
    if (i > 0 && OUTCOMES.includes(t)) answered++;
    if (t === 'unexpected') {
      if (!CASES.includes(text[i + 1])) problems.push(`line ${i}: unexpected ${text[i + 1]}`);
      // after the case, the form (or an odd code's number), then the text
      const reason = text[i + 3];
      if (!reason || reason === '(empty)') problems.push(`line ${i}: no reason`);
    }
  });
  if (asked !== answered) problems.push(`${asked} calls, ${answered} outcomes`);
  if (native) {
    for (const [m, q] of Object.entries(queues)) if (q.length) problems.push(`${m}: ${q.length} answers left`);
    for (const [m, n] of Object.entries(COUNTS))
      if (calls[m] + skipped[m] !== n) problems.push(`${m}: ${calls[m]} asked and ${skipped[m]} skipped of ${n}`);
  }
  console.log(`${label}: ${problems.length ? problems.join('; ') : `every call of ${asked} settled once, each unexpected one with a text`}`);
  if (problems.length) process.exitCode = 1;
}

await run('app', true);
await run('browser page', false);
