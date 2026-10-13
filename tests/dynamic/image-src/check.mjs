// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, over a page with an image "pic" and a copy of it, "copy", whose
// source is the first blob URL the app will make (blob:1) and which has
// not loaded (jsdom loads nothing, so `complete` is told by the
// data-hold attribute). The app gives "pic" three pictures in a row,
// which retires blob:1 and blob:2 (made here in order, and revoked
// here, logged). Prints which are revoked: blob:2 at once (no image
// holds it), blob:1 only once the copy has loaded (a load event), and
// the same for an error on a second held copy of blob:3's successor.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root">' +
  '<img id="pic" alt=""><img id="copy" alt="" src="blob:1" data-hold>' +
  '</div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;
Object.defineProperty(dom.window.HTMLImageElement.prototype, 'complete', {
  get() { return !this.hasAttribute('data-hold'); },
  configurable: true,
});
const revoked = [];
let made = 0;
dom.window.URL.createObjectURL = () => `blob:${++made}`;
dom.window.URL.revokeObjectURL = (url) => { revoked.push(url); };
global.URL = dom.window.URL;
global.Blob = dom.window.Blob;

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-image-src-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
console.log(`pic shows ${document.getElementById('pic').getAttribute('src')}`);
console.log(`revoked while the copy loads: ${revoked.join(' ') || 'none'}`);
const copy = document.getElementById('copy');
copy.removeAttribute('data-hold');
copy.dispatchEvent(new dom.window.Event('load'));
console.log(`revoked once it has loaded: ${revoked.join(' ')}`);
