// Runs dist/debug/app.wasm through the bridge.js that gen wrote with
// produce_bridge_app_book, in jsdom. The app reads the outside file "script"
// (an input whose first file is the script below, one case on each line) and
// plays book content over it: containers, elements, styles, class names,
// sheets in pieces, faces and the writes the ordinary operations may not make.
// jsdom has no constructable style sheets, FontFace or document.fonts, so they
// are stood in for by records of what was adopted and added; the stand-ins show
// what the bridge asks the browser for, not what a browser does with it. After
// each "@snap <name>" the app logs, this prints the stage, the document, the
// adopted sheets, the faces and what the bridge refused since the last one.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const P = '[data-book-container="chap"] ';
const script = [
  /* 0 */ 'A chapter',
  /* 1 */ 'chapter-one',
  /* 2 */ 'color: red; margin: 0',
  /* 3 */ 'color: red; background: url(http://evil.example/x.png)',
  /* 4 */ 'intro lead',
  /* 5 */ `${P}.intro{color:#333}`,
  /* 6 */ `@media (min-width:10px){${P}p{margin:0}}`,
  /* 7 */ 'p{color:red}',
  /* 8 */ '[data-book-container="other"] p{color:red}',
  /* 9 */ `${P}p{color:red} body{color:blue}`,
  /* 10 */ `${P}p{background:url(http://evil.example/y)}`,
  /* 11 */ `${P}p{behavior:url(x)}`,
  /* 12 */ `${P}p{color:red`,
  /* 13 */ `${P}p{ .q{color:red} }`,
  /* 14 */ '@import "x.css";',
  /* 15 */ `@font-face{font-family:x}`,
  /* 16 */ `@keyframes k{from{color:red}}`,
  /* 17 */ `@layer other{${P}p{color:red}}`,
  /* 18 */ `@namespace svg url(x);`,
  /* 19 */ `@page{margin:0}`,
  /* 20 */ `@container (min-width:1px){${P}p{color:red}}`,
  /* 21 */ `/* a comment */${P}p{color:red}`,
  /* 22 */ `${P}.a{color:red}[data-book-`,
  /* 23 */ `container="chap"] .b{color:blue}`,
  /* 24 */ `@media (min-width:1px){@media (min-width:2px){${P}p{color:red}}}`,
  /* 25 */ `color:red;`,
  /* 26 */ 'FONTBYTES',
  /* 27 */ `${P}a, p{color:red}`,
].join('\n');

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"><div id="stage"></div>' +
  '<input id="script" type="file"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;
global.FileReader = dom.window.FileReader;
const file = new dom.window.File([script], 'script.txt');
Object.defineProperty(document.getElementById('script'), 'files', { value: [file] });

// Stand-ins: adopted sheets and faces
class Sheet { replaceSync(text) { this.text = text; } }
global.CSSStyleSheet = Sheet;
document.adoptedStyleSheets = [];
class Face {
  constructor(family, source, descriptors) {
    this.family = family; this.size = source.length; this.weight = descriptors.weight; this.style = descriptors.style;
  }
}
global.FontFace = Face;
const faces = new Set();
document.fonts = { add: (f) => faces.add(f), delete: (f) => faces.delete(f) };

const out = [];
const errors = [];
const logs = [];
const emit = (...parts) => out.push(parts.join(' '));
console.error = (...parts) => errors.push(parts.join(' '));
console.log = (...parts) => logs.push(parts.join(' '));
console.info = console.log;
console.warn = console.log;

function snap(name) {
  emit(`== ${name}`);
  if (!/^book-(sheet|font)/.test(name)) emit(document.getElementById('stage').innerHTML.replace(/></g, '>\n<'));
  emit(`sheets: ${document.adoptedStyleSheets.length}`);
  for (const s of document.adoptedStyleSheets) emit(`  ${s.text}`);
  emit(`faces: ${faces.size}`);
  for (const f of faces) emit(`  ${f.family} ${f.size} bytes weight ${f.weight} ${f.style}`);
  for (const e of errors.splice(0)) emit(`! ${e}`);
}

const src = readFileSync('dist/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-book-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

// the app logs a snap line at the end of each case, in order; the document is
// read when the app calls back, so each snap is taken from the log's own call
const shown = [];
console.log = (...parts) => {
  const line = parts.join(' ').replace(/^\[bats:\w+\] /, '');
  if (line.startsWith('@snap ')) snap(line.slice(6)); else shown.push(line);
};
console.info = console.log;
await loadWASM(readFileSync('dist/debug/app.wasm'), document.getElementById('bats-root'), {});
await new Promise((r) => setTimeout(r, 200));
const log = console.log;
console.log = globalThis.__realLog ?? log;
process.stdout.write(out.join('\n') + '\n');
for (const l of shown) process.stdout.write(`log: ${l}\n`);
