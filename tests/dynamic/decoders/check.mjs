// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with the browser's answers stubbed where jsdom has none, and
// prints each line the app showed (in order of its id), the scrolls and
// the log lines: every answer bridge decodes, in each of its cases.
import 'fake-indexeddb/auto';
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost/#frag', pretendToBeVisual: true });
const win = dom.window;
global.document = win.document;
global.window = win;

// IndexedDB: key "bad" cannot be read, and cannot be written
const getOriginal = IDBObjectStore.prototype.get;
IDBObjectStore.prototype.get = function (key) {
  if (key !== 'bad') return getOriginal.call(this, key);
  const request = {};
  setTimeout(() => request.onerror && request.onerror());
  return request;
};
const putOriginal = IDBObjectStore.prototype.put;
IDBObjectStore.prototype.put = function (value, key) {
  if (key === 'bad') { this.transaction.abort(); return {}; }
  return putOriginal.call(this, value, key);
};

// media queries: "(min-width: 1px)" matches, anything else does not;
// a listener is told the query stopped matching
const changeListeners = [];
win.matchMedia = query => ({
  matches: query === '(min-width: 1px)',
  addEventListener: (_, f) => changeListeners.push(f),
});

// the caret: an offset of 3, or none left of the page
win.document.caretPositionFromPoint = x => (x < 0 ? null : { offset: 3 });
win.Range.prototype.getBoundingClientRect = () => ({ x: 0, y: 0 });
const scrolls = [];
win.Element.prototype.scrollIntoView = function (options) { scrolls.push(`${this.id} ${options.behavior}`); };

// media elements: "player" plays, "refusing" is refused; jsdom's p
// elements made here become audio by their id
win.HTMLElement.prototype.play = function () {
  if (this.id === 'player') return Promise.resolve();
  const e = new Error('refused'); e.name = 'NotAllowedError';
  return Promise.reject(e);
};
Object.defineProperty(win.HTMLElement.prototype, 'currentTime', { get() { return 0.25; }, set() {}, configurable: true });

// the clipboard refuses "no"; it reads "hello", then "", then refuses
const clipboardTexts = ['hello', ''];
Object.defineProperty(win.navigator, 'clipboard', {
  value: {
    writeText: text => (text === 'no' ? Promise.reject(new Error('no')) : Promise.resolve()),
    readText: () => (clipboardTexts.length ? Promise.resolve(clipboardTexts.shift()) : Promise.reject(new Error('refused'))),
  },
});

// push: no subscription, then one, then failing
const pushAnswers = [
  () => Promise.resolve(null),
  () => Promise.resolve({ toJSON: () => ({ endpoint: 'e' }) }),
  () => Promise.reject(new Error('failed')),
];
const pushManager = { getSubscription: () => pushAnswers.shift()(), subscribe: () => pushAnswers.shift()() };
Object.defineProperty(global, 'navigator', {
  value: { serviceWorker: { ready: Promise.resolve({ pushManager }) } }, configurable: true,
});

// files: input "picker" holds "a.txt" (3 bytes) and "bad", which cannot
// be read
global.FileReader = class {
  readAsArrayBuffer(f) {
    setTimeout(() => {
      if (f.name === 'bad') { this.onerror(); return; }
      this.result = new Uint8Array([1, 2, 3]).buffer; this.onload();
    });
  }
};
Object.defineProperty(win.HTMLElement.prototype, 'files', {
  get() { return this.id === 'picker' ? [{ name: 'a.txt' }, { name: 'bad' }] : undefined; },
  configurable: true,
});

// notifications: granted, then dismissed, then denied
const answers = ['granted', 'default', 'denied'];
global.Notification = { requestPermission: () => Promise.resolve(answers.shift()) };

// the selection: each range it is given and each time it is emptied
const selections = [];
const addRange = win.Selection.prototype.addRange;
win.Selection.prototype.addRange = function (range) {
  selections.push(`select "${range.toString()}"`);
  return addRange.call(this, range);
};
const removeAllRanges = win.Selection.prototype.removeAllRanges;
win.Selection.prototype.removeAllRanges = function () {
  selections.push('empty');
  return removeAllRanges.call(this);
};

const logs = [];
const consoleLog = console.log;
console.log = (...parts) => logs.push(parts.join(' '));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-decoders-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
Object.defineProperty(win.document, 'visibilityState', { value: 'hidden', configurable: true });
for (const f of changeListeners) f({ matches: false });
await new Promise(r => setTimeout(r, 500));

console.log = consoleLog;
const lines = [...root.children].map(e => `${e.id}: ${e.textContent}`).sort();
for (const l of lines) console.log(l);
for (const s of scrolls) console.log(`scroll ${s}`);
for (const s of selections) console.log(`selection ${s}`);
for (const l of logs.filter(l => l.startsWith('[bats:'))) console.log(l);
