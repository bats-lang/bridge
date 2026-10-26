// The old forms of bridge's JS (produce_bridge, produce_bridge_app) are still
// there beside the ones with the platform atom (bridge#191): the bridge.js
// pwa wrote with produce_bridge_app runs an app, and begins with the whole
// of bridge-plain.js, which produce_bridge wrote; neither holds the platform
// atom, and both fit the old bounds (119271 and 121271 bytes).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const plain = readFileSync('dist/pwa/bridge-plain.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
console.log(`bridge.js begins with bridge-plain.js: ${src.startsWith(plain)}`);
console.log(`bridge-plain.js within the old bound of produce_bridge: ${Buffer.byteLength(plain) <= 119271}`);
console.log(`bridge.js within the old bound of produce_bridge_app: ${Buffer.byteLength(src) <= 121271}`);
for (const [name, text] of [['bridge.js', src], ['bridge-plain.js', plain]]) {
  console.log(`${name} has no platform atom: ${!text.includes('batsJsPlatformFact') && !text.includes('bats_js_platform_')}`);
  console.log(`${name} has the other atoms: ${text.includes('bats_js_is_native_platform') && text.includes('bats_js_timezone_offset')}`);
}

const tmp = join(tmpdir(), `bridge-old-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);
const dom = new JSDOM(
  '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
const win = dom.window;
global.document = win.document;
global.window = win;
win.addEventListener('hashchange', e => console.log(`hash: #${decodeURIComponent(new URL(e.newURL).hash.slice(1))}`));
await loadWASM(readFileSync('dist/pwa/app.wasm'), win.document.getElementById('bats-root'), {});
await new Promise(r => setTimeout(r, 100));
console.log('done');
