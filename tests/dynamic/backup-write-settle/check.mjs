// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing the native app: Capacitor with Filesystem, whose writeFile
// each case plays differently. The app writes a backed-up file with
// backup_file_write_answer and then, again, with the old backup_file_write.
// The cases: the write resolves with the plugin's answer, resolves with
// nothing, is rejected with an error, is rejected with nothing, throws as
// it is called (with an error, and with nothing); the app has no
// Filesystem plugin; the bytes failing to read, and a code the bridge
// never gives. Prints each write made
// and what the app says: the outcome of backup_file_write_answer (every
// constructor) and of the old backup_file_write, which says only written or
// not written (bridge#186, bridge#236).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-backup-write-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with the bytes failing to read (the app cannot make
// them fail, the wasm memory is there), and with a code it never gives (-9)
// where a rejection had -2, to pass the thrown reading and
// BackupWriteUnexpected through the app
const bytesRead = "base64(readBytes(bp, bl))";
if (!head.includes(bytesRead)) throw new Error('bridge.js: the bytes read not found');
const rejectedCode = 'backupWriteSaid(id, x, -2)';
if (!head.includes(rejectedCode)) throw new Error('bridge.js: the rejection case not found');
const loads = {
  real: await load('real', head),
  unreadable: await load('unreadable', head.replace(bytesRead,
    "(() => { throw (e => { delete e.stack; return e; })(new Error('bytes unreadable')); })()")),
  unexpected: await load('unexpected', head.replace(rejectedCode, 'backupWriteSaid(id, x, -9)')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };
const text = b64 => Buffer.from(b64, 'base64').toString('utf-8');

async function play(label, writeFile, { plugins = true, bridge = 'real' } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  globalThis.Capacitor = {
    isNativePlatform: () => true,
    Plugins: plugins ? { Filesystem: { writeFile: o => {
      console.log(`write ${o.directory} ${o.path}: ${text(o.data)}`);
      return writeFile(o);
    } } } : {},
  };
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    console.log(`hash: #${line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

await play('the plugin writes the file', () => Promise.resolve({ uri: 'file:///note' }));
await play('the plugin writes the file and answers nothing', () => Promise.resolve());
await play('the plugin rejects the write: its own outcome, with the error',
  () => Promise.reject(clean(new Error('disk full'))));
await play('the plugin rejects with nothing',
  () => Promise.reject());
await play('the write throws as it is called: its own outcome, with the error',
  () => { throw clean(new Error('threw')); });
await play('the write throws nothing',
  () => { throw undefined; });
await play('there is no Filesystem plugin', () => Promise.resolve({}), { plugins: false });
await play('the bytes fail to read: a thrown write',
  () => Promise.resolve({}), { bridge: 'unreadable' });
await play('a code the bridge never gives is BackupWriteUnexpected',
  () => Promise.reject(clean(new Error('x'))), { bridge: 'unexpected' });
console.log('done');
