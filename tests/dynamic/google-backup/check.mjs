// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing the native app: Capacitor with its GoogleSignIn (the
// first sign-in gives a token and an address, the second finds no
// account) and Filesystem (files kept in a map). Prints each call.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
const win = dom.window;
global.document = win.document;
global.window = win;

const files = new Map();
let signIns = 0;
const text = b64 => Buffer.from(b64, 'base64').toString('utf-8');
globalThis.Capacitor = {
  isNativePlatform: () => true,
  Plugins: {
    GoogleSignIn: {
      initialize: o => { console.log(`initialize: ${o.clientId} [${o.scopes.join(', ')}]`); return Promise.resolve(); },
      signIn: () => {
        signIns += 1;
        console.log(`signIn ${signIns}`);
        if (signIns === 1) return Promise.resolve({ accessToken: 'token-123', email: 'reader@example.com' });
        return Promise.reject(Object.assign(new Error('none'), { code: 'NO_CREDENTIAL_AVAILABLE' }));
      },
      signOut: () => { console.log('signOut'); return Promise.resolve(); },
    },
    Filesystem: {
      writeFile: o => { console.log(`write ${o.directory} ${o.path}: ${text(o.data)}`); files.set(o.path, o.data); return Promise.resolve({ uri: 'file:///' + o.path }); },
      stat: o => files.has(o.path) ? Promise.resolve({ type: 'file' }) : Promise.reject(new Error('File does not exist')),
      readFile: o => { console.log(`read ${o.directory} ${o.path}`); return Promise.resolve({ data: files.get(o.path) }); },
    },
  },
};
const settle = () => new Promise(r => setTimeout(r, 300));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-google-backup-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await settle();
