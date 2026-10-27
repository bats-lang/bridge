// Runs dist/pwa/app.wasm through the bridge.js that pwa generated, in
// jsdom, playing the native app: Capacitor with Filesystem, whose readdir
// and readFile each case plays differently. The app reads a backed-up file
// with backup_file_read_answer and then, again, with the old
// backup_file_read. The cases: the file is there; no such file; no backup
// directory; the app has no Filesystem plugin; the file holds nothing; the
// listing rejects (with an error, and with nothing); the read rejects; the
// listing throws as it is called; the read answers nothing; the data is no
// base64; the listing is no list; a code the bridge never gives; a blob
// handle the bridge never gave. Prints each call made and what the app
// says: the outcome of backup_file_read_answer (every constructor) and of
// the old backup_file_read, which says only found, none or unreadable
// (bridge#186, bridge#239).
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const head = src.slice(0, boot);

async function load(label, text) {
  const tmp = join(tmpdir(), `bridge-backup-read-${label}-${process.pid}.mjs`);
  writeFileSync(tmp, text + '\n');
  const { loadWASM } = await import(tmp);
  unlinkSync(tmp);
  return loadWASM;
}
// The same bridge.js with a code it never gives (-9) where a rejection had
// the code it says, and with a blob handle it never gave where the bytes
// were kept, to pass BackupReadUnexpected through the app
const rejectedCode = 'backupReadSaid(id, x, said)';
if (!head.includes(rejectedCode)) throw new Error('bridge.js: the rejection case not found');
const keptBlob = 'return u.length ? pendBlob(u) : -2;';
if (!head.includes(keptBlob)) throw new Error('bridge.js: the kept blob not found');
const loads = {
  real: await load('real', head),
  unexpected: await load('unexpected', head.replace(rejectedCode, 'backupReadSaid(id, x, -9)')),
  handle: await load('handle', head.replace(keptBlob, 'return 424242;')),
};
const wasm = readFileSync('dist/pwa/app.wasm');
const settle = () => new Promise(r => setTimeout(r, 100));

// An error without its stack, which names this machine's paths
const clean = e => { delete e.stack; return e; };
const b64 = s => Buffer.from(s).toString('base64');

// The Filesystem plugin: backup/note is in the listings unless said
// otherwise, readFile answers with the data given
function filesystem({ listing, readdir, readFile = () => Promise.resolve({ data: b64('contents') }) } = {}) {
  const lists = listing || { '': ['backup'], backup: ['note'] };
  return {
    readdir: o => {
      console.log(`readdir ${o.directory} "${o.path}"`);
      return readdir ? readdir(o) : Promise.resolve({ files: (lists[o.path] || []).map(name => ({ name, type: 'file' })) });
    },
    readFile: o => { console.log(`read ${o.directory} ${o.path}`); return readFile(o); },
  };
}

async function play(label, filesystemPlugin, { bridge = 'real' } = {}) {
  console.log(`== ${label}`);
  const dom = new JSDOM(
    '<!DOCTYPE html><html><head></head><body><div id="bats-root"></div></body></html>',
    { url: 'http://localhost', pretendToBeVisual: true });
  const win = dom.window;
  global.document = win.document;
  global.window = win;
  globalThis.Capacitor = {
    isNativePlatform: () => true,
    Plugins: filesystemPlugin ? { Filesystem: filesystemPlugin } : {},
  };
  win.addEventListener('hashchange', e => {
    const hash = new URL(e.newURL).hash.slice(1);
    let line; try { line = decodeURIComponent(hash); } catch (x) { line = `(raw) ${hash}`; }
    // an error the engine made carries a stack that names this machine's
    // paths and a message worded by this engine's version
    console.log(`hash: #${line.includes('"stack":') ? line.replace(/"stack":"[^"]*"/, '"stack":"(stack)"').replace(/,"message":"[^"]*"/, '') : line}`);
  });
  await loads[bridge](wasm, win.document.getElementById('bats-root'), {});
  await settle();
}

await play('the file is there', filesystem());
await play('no such file in the backup directory', filesystem({ listing: { '': ['backup'], backup: [] } }));
await play('no backup directory', filesystem({ listing: { '': [] } }));
await play('there is no Filesystem plugin', null);
await play('the file holds nothing', filesystem({ readFile: () => Promise.resolve({ data: '' }) }));
await play('the listing rejects: its own outcome, with the error',
  filesystem({ readdir: () => Promise.reject(clean(new Error('no listing'))) }));
await play('the listing rejects with nothing',
  filesystem({ readdir: () => Promise.reject() }));
await play('the read rejects: its own outcome, with the error',
  filesystem({ readFile: () => Promise.reject(clean(new Error('unreadable'))) }));
await play('the listing throws as it is called: its own outcome, with the error',
  filesystem({ readdir: () => { throw clean(new Error('threw')); } }));
await play('the listing throws nothing',
  filesystem({ readdir: () => { throw undefined; } }));
await play('the read answers nothing: reading the answer threw',
  filesystem({ readFile: () => Promise.resolve() }));
await play('the data is no base64: decoding threw',
  filesystem({ readFile: () => Promise.resolve({ data: '!!!' }) }));
await play('the listing is no list: reading the answer threw',
  filesystem({ readdir: () => Promise.resolve({ files: 5 }) }));
await play('a code the bridge never gives is BackupReadUnexpected',
  filesystem({ readFile: () => Promise.reject(clean(new Error('x'))) }), { bridge: 'unexpected' });
await play('a blob handle the bridge never gave is BackupReadUnexpected',
  filesystem(), { bridge: 'handle' });
console.log('done');
