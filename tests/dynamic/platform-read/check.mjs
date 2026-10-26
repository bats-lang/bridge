// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in jsdom,
// with a stand-in for each platform the page can run on: navigator's
// userAgent, userAgentData.platform, platform and maxTouchPoints, and
// Capacitor's getPlatform(). The app reads the platform and says the engine,
// the system and the shell (platform.bats), every constructor of them, each
// Unexpected with the fact it keeps. The cases: the documented platforms
// (Chrome, Edge, Firefox, Safari, an iPad in desktop mode, WKWebView, an
// Android WebView, the Capacitor app, a Chromebook), the nasty facts (none,
// empty, not a string, a read that throws, a text over the 2048 bytes read,
// a lone surrogate, a touch count that is no count) and the answers JS never
// gives (bridge#191).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-platform-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with a code it never gives (-9) and with a handle it
// never made (999999) where a property that is not there had 0
const absent = 'if (v === undefined) return 0;';
if (!head.includes(absent)) throw new Error('bridge.js: the absent case not found');
const loads = {
  real: await load('real', head),
  code: await load('code', head.replace(absent, 'if (v === undefined) return -9;')),
  handle: await load('handle', head.replace(absent, 'if (v === undefined) return 999999;')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

const CHROME_WIN = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const EDGE_WIN = CHROME_WIN + ' Edg/130.0.0.0';
const CHROME_ANDROID = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
const WEBVIEW_ANDROID = 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP1A; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36';
const CHROME_LINUX = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const CHROME_CROS = 'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
const SAFARI_MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
const SAFARI_IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const SAFARI_IPAD = 'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
const CHROME_IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0.0.0 Mobile/15E148 Safari/604.1';
const FIREFOX_IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/130.0 Mobile/15E148 Safari/605.1.15';
const WKWEBVIEW = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const FIREFOX_LINUX = 'Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0';
const FIREFOX_MAC = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:130.0) Gecko/20100101 Firefox/130.0';
const FIREFOX_WIN = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0';
const FIREFOX_ANDROID = 'Mozilla/5.0 (Android 14; Mobile; rv:130.0) Gecko/130.0 Firefox/130.0';

const thrower = (e) => () => { throw e; };

// A navigator with the given facts; a fact given as {get: f} is a getter
function navigatorOf({ ua, uaData, platform, touch }) {
  const n = {};
  const put = (name, v) => {
    if (v === undefined) return;
    if (v && typeof v == 'object' && 'get' in v && Object.keys(v).length == 1) Object.defineProperty(n, name, { get: v.get });
    else Object.defineProperty(n, name, { value: v });
  };
  put('userAgent', ua); put('userAgentData', uaData); put('platform', platform); put('maxTouchPoints', touch);
  return n;
}

async function play(label, facts, { capacitor, bridge = 'real', noNavigator = false } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  Object.defineProperty(globalThis, 'navigator', { value: noNavigator ? undefined : navigatorOf(facts), configurable: true, writable: true });
  if (capacitor === undefined) delete globalThis.Capacitor; else globalThis.Capacitor = capacitor;
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    // The engine's own wording of a read through undefined is named
    line = line.replace(/Cannot read properties of \w+ \(reading '\w+'\)/g, "(the engine's TypeError)");
    // A stack names this machine's paths, and a run of one letter is long
    line = line.replace(/"stack":"[^"]*",?/g, '').replace(/(.)\1{30,}/gs, (m, c) => `${c}*${m.length}`);
    console.log(`hash: #${line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

// ---- the documented platforms
await play('Chrome on Windows', { ua: CHROME_WIN, uaData: { platform: 'Windows' }, platform: 'Win32', touch: 0 });
await play('Edge on Windows', { ua: EDGE_WIN, uaData: { platform: 'Windows' }, platform: 'Win32', touch: 0 });
await play('Chrome on Android', { ua: CHROME_ANDROID, uaData: { platform: 'Android' }, platform: 'Linux armv81', touch: 5 });
await play('Chrome on Linux', { ua: CHROME_LINUX, uaData: { platform: 'Linux' }, platform: 'Linux x86_64', touch: 0 });
await play('Chrome on a Chromebook', { ua: CHROME_CROS, uaData: { platform: 'Chrome OS' }, platform: 'Linux x86_64', touch: 0 });
await play('Safari on a Mac', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 0 });
await play('Safari on an iPhone', { ua: SAFARI_IPHONE, platform: 'iPhone', touch: 5 });
await play('Safari on an iPad', { ua: SAFARI_IPAD, platform: 'iPad', touch: 5 });
await play('Safari on an iPad in desktop mode (a Macintosh with touch points)', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 5 });
await play('a Macintosh with two touch points', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 2 });
await play('a Macintosh with one touch point', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 1 });
await play('a Macintosh with no maxTouchPoints', { ua: SAFARI_MAC, platform: 'MacIntel' });
await play('Chrome on an iPhone (WebKit)', { ua: CHROME_IPHONE, platform: 'iPhone', touch: 5 });
await play('Firefox on an iPhone (WebKit)', { ua: FIREFOX_IPHONE, platform: 'iPhone', touch: 5 });
await play('Firefox on Linux', { ua: FIREFOX_LINUX, platform: 'Linux x86_64', touch: 0 });
await play('Firefox on a Mac', { ua: FIREFOX_MAC, platform: 'MacIntel', touch: 0 });
await play('Firefox on Windows', { ua: FIREFOX_WIN, platform: 'Win32', touch: 0 });
await play('Firefox on Android', { ua: FIREFOX_ANDROID, platform: 'Linux armv81', touch: 5 });
// ---- the app shells
await play('an Android WebView with no Capacitor', { ua: WEBVIEW_ANDROID, platform: 'Linux armv81', touch: 5 });
await play('a WKWebView with no Capacitor', { ua: WKWEBVIEW, platform: 'iPhone', touch: 5 });
await play('the Capacitor app on Android', { ua: WEBVIEW_ANDROID, platform: 'Linux armv81', touch: 5 }, { capacitor: { getPlatform: () => 'android' } });
await play('the Capacitor app on iOS', { ua: WKWEBVIEW, platform: 'iPhone', touch: 5 }, { capacitor: { getPlatform: () => 'ios' } });
await play('Capacitor on the web in a browser', { ua: CHROME_WIN, platform: 'Win32', touch: 0 }, { capacitor: { getPlatform: () => 'web' } });
await play('Capacitor on the web in an Android WebView', { ua: WEBVIEW_ANDROID, platform: 'Linux armv81', touch: 5 }, { capacitor: { getPlatform: () => 'web' } });
await play('Capacitor names a platform it does not have', { ua: CHROME_WIN, platform: 'Win32', touch: 0 }, { capacitor: { getPlatform: () => 'electron' } });
await play('Capacitor names no string', { ua: CHROME_WIN, platform: 'Win32', touch: 0 }, { capacitor: { getPlatform: () => 7 } });
await play('Capacitor throws', { ua: CHROME_WIN, platform: 'Win32', touch: 0 }, { capacitor: { getPlatform: thrower(clean(new Error('no platform'))) } });
await play('Capacitor throws nothing', { ua: CHROME_WIN, platform: 'Win32', touch: 0 }, { capacitor: { getPlatform: thrower(undefined) } });
// ---- the nasty facts
await play('a user agent no rule knows', { ua: 'curl/8.0', platform: '', touch: 0 });
await play('an empty user agent', { ua: '', platform: '', touch: 0 });
await play('no user agent at all', { platform: 'Win32', touch: 0 });
await play('a user agent that is a number', { ua: 42, platform: 'Win32', touch: 0 });
await play('a user agent that is an object with a cycle', { ua: (() => { const o = {}; o.o = o; return o; })(), platform: 'Win32' });
await play('a user agent that is null', { ua: null });
await play('a user agent that throws as it is read', { ua: { get: thrower(clean(new Error('no agent'))) }, platform: 'Win32' });
await play('a user agent that throws nothing', { ua: { get: thrower(undefined) } });
await play('a user agent that throws a thing nothing can write', { ua: { get: thrower(Object.create(null, { toJSON: { get: thrower(1) } })) } });
await play('a user agent of 3000 bytes, Firefox/ past the 2048 read', { ua: 'x'.repeat(2990) + ' Firefox/1', platform: 'Win32' });
await play('a user agent of 2048 bytes, Firefox/ at its end', { ua: 'x'.repeat(2048 - 9) + 'Firefox/1', platform: 'Win32' });
await play('a user agent of 5000 bytes no rule knows', { ua: 'y'.repeat(5000), platform: '' });
await play('a user agent with a lone surrogate', { ua: 'bot \ud800 1.0', platform: '' });
await play('a user agent with Firefox/ and a lone surrogate', { ua: 'bot \ud800 Firefox/1', platform: 'Linux x86_64' });
// ---- the system from the other facts
await play('a user agent no rule knows, userAgentData says Windows', { ua: 'bot', uaData: { platform: 'Windows' }, platform: 'MacIntel', touch: 0 });
await play('a user agent no rule knows, navigator.platform says MacIntel', { ua: 'bot', platform: 'MacIntel', touch: 0 });
await play('a user agent no rule knows, userAgentData throws, platform says Linux', { ua: 'bot', uaData: { get platform() { throw clean(new Error('no data')); } }, platform: 'Linux x86_64' });
await play('userAgentData is null', { ua: 'bot', uaData: null, platform: 'Linux x86_64' });
await play('a Macintosh with maxTouchPoints a string', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 'five' });
await play('a Macintosh with maxTouchPoints NaN', { ua: SAFARI_MAC, platform: 'MacIntel', touch: NaN });
await play('a Macintosh with maxTouchPoints -1', { ua: SAFARI_MAC, platform: 'MacIntel', touch: -1 });
await play('a Macintosh with maxTouchPoints 1.5', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 1.5 });
await play('a Macintosh with maxTouchPoints 1234567', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 1234567 });
await play('a Macintosh with maxTouchPoints 1e21', { ua: SAFARI_MAC, platform: 'MacIntel', touch: 1e21 });
await play('a Macintosh with maxTouchPoints that throws', { ua: SAFARI_MAC, platform: 'MacIntel', touch: { get: thrower(clean(new Error('no touch'))) } });
await play('an Android with maxTouchPoints a string (not read)', { ua: CHROME_ANDROID, touch: 'five' });
// ---- no navigator, and the answers JS never gives
await play('no navigator', {}, { noNavigator: true });
await play('a code the bridge never gives', { ua: CHROME_WIN, platform: 'Win32' }, { bridge: 'code' });
await play('no user agent, a code the bridge never gives', {}, { bridge: 'code' });
await play('no user agent, a handle the bridge never made', {}, { bridge: 'handle' });
await play('a handle the bridge never made', { ua: CHROME_WIN, platform: 'Win32' }, { bridge: 'handle' });
console.log('done');
