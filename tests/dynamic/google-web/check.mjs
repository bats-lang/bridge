// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, as a browser page (no Capacitor): Google Identity Services,
// already loaded, is played. The first request gives a token, the
// second is closed by the reader, and revoking logs the token. Prints
// each call.
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost', pretendToBeVisual: true });
const win = dom.window;
global.document = win.document;
global.window = win;

let requests = 0;
win.google = {
  accounts: {
    oauth2: {
      initTokenClient: o => {
        console.log(`initTokenClient: ${o.client_id} ${o.scope}`);
        return {
          requestAccessToken: () => {
            requests += 1;
            console.log(`requestAccessToken ${requests}`);
            setTimeout(() => requests === 1 ? o.callback({ access_token: 'web-token-1' }) : o.error_callback({ type: 'popup_closed' }), 10);
          },
        };
      },
      revoke: (token, done) => { console.log(`revoke: ${token}`); done(); },
    },
  },
};
const settle = () => new Promise(r => setTimeout(r, 300));

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-google-web-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);

const root = document.getElementById('bats-root');
await loadWASM(readFileSync('dist/pwa/app.wasm'), root, {});
await settle();
if (win.document.querySelector('script[src*="accounts.google.com"]')) console.log('loaded the script again');
