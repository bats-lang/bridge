// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, with the browser's offer to install as each case plays it: the user
// accepting or dismissing, no offer, prompt() rejecting, throwing as it is
// called and rejecting with nothing, the user's choice rejecting, a choice
// whose outcome throws when the bridge reads it, an outcome that is neither
// accepted nor dismissed, one that is nothing, and a code the bridge never
// gives. Each prints the platform call made and what the app says: the
// outcome of install_prompt_answer (every constructor) and then, on the next
// offer of the same kind, of the old install_prompt, which says only
// accepted, dismissed or unavailable (bridge#186, bridge#229).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');

// The bridge keeps the offer from the page's start, with the events it
// listens to on the global object: the module is loaded with a stand-in for
// addEventListener that keeps its handlers, and the offers are delivered
// through them, as the browser delivers beforeinstallprompt.
async function load(code, tag) {
  const handlers = {};
  globalThis.addEventListener = (type, handler) => { handlers[type] = handler; };
  const tmp = join(tmpdir(), `bridge-install-settle-${tag}-${process.pid}.mjs`);
  writeFileSync(tmp, code + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  delete globalThis.addEventListener;
  return { loadWASM, handlers };
}
const base = src.slice(0, boot);
// The same bridge.js with a code it never gives (-9) where the thrown
// answer's -4 was, to pass InstallAnswerUnexpected through the app
const oddCode = base.replace('installSaid(id, x, -4)', 'installSaid(id, x, -9)');
if (oddCode === base) throw new Error('bridge.js: the answer thrown case not found');
const real = await load(base, 'real');
const odd = await load(oddCode, 'odd');
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };

// An offer the browser fired: prompt() and userChoice as the case plays them
const offerOf = how => ({
  preventDefault() {},
  prompt() { console.log('offer.prompt()'); return how.prompt(); },
  get userChoice() { return how.choice(); },
});
const chosen = outcome => ({ prompt: () => Promise.resolve(), choice: () => Promise.resolve({ outcome }) });

async function play(label, how, loaded = real) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  globalThis.Capacitor = undefined;
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  if (how) loaded.handlers.beforeinstallprompt(offerOf(how));
  await loaded.loadWASM(wasm, win.document.getElementById('bats-root'), {});
  await settle();
  // the next offer, for the old install_prompt
  loaded.handlers.beforeinstallprompt(offerOf(how || chosen('accepted')));
  await settle();
  loaded.handlers.appinstalled();
}

await play('the user accepts', chosen('accepted'));
await play('the user dismisses', chosen('dismissed'));
await play('there is no offer', null);
await play('prompt rejects: its own outcome, with the error',
  { prompt: () => Promise.reject(clean(Object.assign(new Error('denied'), { code: 'NotAllowedError' }))), choice: () => Promise.resolve({ outcome: 'accepted' }) });
await play('prompt rejects with nothing',
  { prompt: () => Promise.reject(undefined), choice: () => Promise.resolve({ outcome: 'accepted' }) });
await play('prompt throws as it is called',
  { prompt: () => { throw clean(new Error('threw')); }, choice: () => Promise.resolve({ outcome: 'accepted' }) });
await play('the user\'s choice rejects',
  { prompt: () => Promise.resolve(), choice: () => Promise.reject(clean(new Error('no choice'))) });
await play('the outcome throws when it is read',
  { prompt: () => Promise.resolve(), choice: () => Promise.resolve({ get outcome() { throw clean(new Error('getter')); } }) });
await play('the outcome is neither accepted nor dismissed',
  chosen('maybe'));
await play('the outcome is nothing',
  chosen(undefined));
await play('a code the bridge never gives is InstallAnswerUnexpected',
  { prompt: () => Promise.resolve(), choice: () => Promise.resolve({ get outcome() { throw clean(new Error('getter')); } }) }, odd);
console.log('done');
