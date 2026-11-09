// Runs dist/pwa/app.wasm through the bridge.js that gen wrote (with the
// image error atom), in jsdom, over a page with an image "broken" whose
// source is corrupt, an image "fine" that draws, an image with no id, a
// script that fails to load, and a div. jsdom decodes no image, so the
// engine's events are played: a failed image gets a non-bubbling `error`
// event, a drawn one a `load` event. The app logs each image it is told
// failed (history.pushState with the node id, spied here). Prints what a
// bubble-phase listener on the document hears (nothing: the event does not
// bubble) and every call of the app's listener, which must be one for
// "broken" and none for the others (bridge#277).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const corrupt = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/not-an-image';
const png = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root">' +
  `<img id="broken" alt="" src="${corrupt}">` +
  `<img id="fine" alt="" src="${png}">` +
  `<img alt="" src="${corrupt}" data-anonymous>` +
  '<script id="script-failed"></script><div id="plain"></div>' +
  '</div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
const win = dom.window;
global.document = win.document;
global.window = win;
const push = win.history.pushState.bind(win.history);
win.history.pushState = (state, title, url) => { console.log(`app: ${url}`); push(state, title, url); };

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
console.log(`bridge.js within the bound of produce_bridge_app_image_error: ${Buffer.byteLength(src) <= 124883}`);
console.log(`bridge.js has the platform atom and the image error atom: ${src.includes('bats_js_platform_fact') && src.includes('bats_js_listen_image_error')}`);
const tmp = join(tmpdir(), `bridge-image-error-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const bubbled = [];
win.document.addEventListener('error', (e) => bubbled.push(e.target.id || 'no id'));
await loadWASM(readFileSync('dist/pwa/app.wasm'), document.getElementById('bats-root'), {});

const settle = () => new Promise(r => setTimeout(r, 100));
const error = (el) => el.dispatchEvent(new win.Event('error', { bubbles: false }));
const el = (id) => document.getElementById(id);
await settle();
console.log('-- the image that draws');
el('fine').dispatchEvent(new win.Event('load'));
await settle();
console.log('-- the corrupt image');
error(el('broken'));
await settle();
console.log('-- an image with no id');
error(document.querySelector('[data-anonymous]'));
await settle();
console.log('-- a script and a div');
error(el('script-failed'));
error(el('plain'));
await settle();
console.log(`a bubble-phase listener on the document heard: ${bubbled.join(' ') || 'nothing'}`);
console.log('done');
