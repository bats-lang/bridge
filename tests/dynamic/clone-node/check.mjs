// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, over a page with an element "page" (ids, a tabindex, a gesture
// region and a link inside it, and markup the stream would refuse: an
// event handler, two of them side by side (so a walk that skips the
// next attribute after a removal fails), a javascript: URL, a script,
// SVG, customized built-ins (by attribute and by script) and shadow
// roots), a form, an svg, and an element "sheet" holding something
// else. Prints the document's body after the app has cloned "page" into
// "sheet" twice (CLONE_NODE) and changed and scrolled the first clone,
// where it is scrolled, and the ids in the document.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root">' +
  '<div id="page" class="caf" tabindex="0" data-gesture-region="1" role="document">' +
  '<p id="c0">One <a id="c1" href="#x" tabindex="0">link</a></p><p id="c2">Two</p>' +
  '<span onclick="go()" onmouseover="go()">On</span><a href="javascript:go()">Run</a><script>go()</script>' +
  '<svg><set attributeName="href" to="javascript:go()"></set></svg>' +
  '<p is="x-para">Built in</p><div id="host" class="shadowed">Host</div><div class="own-shadow">Own</div></div>' +
  '<form id="form"><input id="field"></form><svg id="drawing"><rect></rect></svg>' +
  '<div id="sheet"><span id="old">old</span></div>' +
  '</div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;
// A shadow root, which the stream cannot make. jsdom neither clones one
// (clonable) nor lets a test set one, so shadowRoot is stood in for by a
// getter: "shadowed" is a host whose copy carries an open root (a
// clonable one: the getter answers only off the document, where the
// copy is while it is checked), "own-shadow" one whose source has an
// open root that the copy does not carry (answered only in the
// document). It shows the check is on the copy, not the source; it
// cannot show what a browser clones
Object.defineProperty(dom.window.HTMLElement.prototype, 'shadowRoot', {
  get() {
    if (this.classList.contains('shadowed')) return this.isConnected ? null : {};
    if (this.classList.contains('own-shadow')) return this.isConnected ? {} : null;
    return null;
  },
  configurable: true,
});
// A customized built-in made by script: a <q> whose constructor is
// x-quote's, with no is attribute. jsdom has no customElements.getName,
// so it is given one over what this test defines
const names = new Map();
class Quote extends dom.window.HTMLQuoteElement {}
dom.window.customElements.define('x-quote', Quote, { extends: 'q' });
names.set(Quote, 'x-quote');
dom.window.customElements.getName = (constructor) => names.get(constructor) ?? null;
global.customElements = dom.window.customElements;
const quote = document.createElement('q', { is: 'x-quote' });
quote.textContent = 'Quoted';
document.getElementById('page').appendChild(quote);

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-clone-node-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
try {
  await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
} catch (error) {
  console.log(`stopped: ${error.message}`);
}
console.log(root.innerHTML.replace(/></g, '>\n<'));
const copy = document.getElementById('copy');
console.log(`copy scrolled to ${copy.scrollLeft}, ${copy.scrollTop}`);
console.log(`ids: ${[...document.querySelectorAll('[id]')].map((el) => el.id).join(' ')}`);
