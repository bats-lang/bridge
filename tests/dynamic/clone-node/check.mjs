// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, over a page with an element "page" (ids, a tabindex, a gesture
// region and a link inside it, and markup the stream would refuse: an
// event handler, a javascript: URL, a script and SVG), a form, and an
// element "sheet" holding something else. Prints the document's body after the app has cloned "page" into
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
  '<span onclick="go()">On</span><a href="javascript:go()">Run</a><script>go()</script>' +
  '<svg><set attributeName="href" to="javascript:go()"></set></svg></div>' +
  '<form id="form"><input id="field"></form>' +
  '<div id="sheet"><span id="old">old</span></div>' +
  '</div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;
// jsdom lays nothing out, so a scroll is only what was set
for (const name of ['scrollLeft', 'scrollTop']) {
  Object.defineProperty(dom.window.HTMLElement.prototype, name, {
    get() { return this['_' + name] || 0; },
    set(v) { this['_' + name] = v; },
    configurable: true,
  });
}

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-clone-node-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
console.log(root.innerHTML.replace(/></g, '>\n<'));
const copy = document.getElementById('copy');
console.log(`copy scrolled to ${copy.scrollLeft}, ${copy.scrollTop}`);
console.log(`ids: ${[...document.querySelectorAll('[id]')].map((el) => el.id).join(' ')}`);
