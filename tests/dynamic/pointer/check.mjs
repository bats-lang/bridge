// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, sending pointer events to the root (a touch drag to the left,
// then a mouse that moves past 4 px) and running animation frames by
// hand; prints what the app logged and the pointers captured.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root" data-gesture-region="1"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
const win = dom.window;
global.document = win.document;
global.window = win;
Object.defineProperty(win, 'innerWidth', { value: 400, configurable: true });

const frames = [];
win.requestAnimationFrame = (f) => { frames.push(f); return frames.length; };
let clock = 1000;
const runFrame = () => { const fs = frames.splice(0); clock += 16; fs.forEach(f => f(clock)); };
const captured = [];
const lines = [];
const consoleLog = console.log;
console.log = (...parts) => lines.push(parts.join(' '));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-pointer-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
root.setPointerCapture = (id) => captured.push(id);
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
const settle = () => new Promise(r => setTimeout(r, 20));
const pointer = (type, id, x, y, kind, button) => {
  const e = new win.Event(type, { bubbles: true });
  Object.assign(e, { pointerId: id, clientX: x, clientY: y, pointerType: kind, button: button || 0 });
  Object.defineProperty(e, 'timeStamp', { value: clock });
  root.dispatchEvent(e);
};
const step = async (label, f) => { lines.push(label); f(); await settle(); };

await step('touch down', () => pointer('pointerdown', 1, 300, 100, 'touch'));
await step('moves', () => { pointer('pointermove', 1, 280, 101, 'touch'); pointer('pointermove', 1, 250, 102, 'touch'); });
await step('frame', runFrame);
await step('far move', () => pointer('pointermove', 1, 150, 103, 'touch'));
await step('up', () => pointer('pointerup', 1, 140, 103, 'touch'));
await step('frame', runFrame);
await step('mouse down', () => pointer('pointerdown', 2, 200, 100, 'mouse'));
await step('mouse moves 6 px', () => pointer('pointermove', 2, 206, 100, 'mouse'));
await step('frame', runFrame);
await step('hidden', () => win.document.dispatchEvent(new win.Event('visibilitychange')));
await step('frame', runFrame);
console.log = consoleLog;
for (const l of lines) console.log(l);
console.log(`captured: ${captured.join(',')}`);
