// Drives bridge's IndexedDB atoms (idb.bats and the JS bridge writes for
// them) through the real wasm app in src/bin/app.bats, against
// fake-indexeddb. The app runs a script this file hands it (every command
// of it at once, in one tick) and reports each outcome as a tag; each
// scenario prints what it saw, and the output is compared with `expected`.
import 'fake-indexeddb/auto';
import { IDBFactory } from 'fake-indexeddb';
import { JSDOM } from 'jsdom';
import { readFileSync, writeFileSync, unlinkSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const dom = new JSDOM(
  '<!DOCTYPE html><html><body><div id="bats-root"></div></body></html>',
  { url: 'http://localhost/', pretendToBeVisual: true });
global.document = dom.window.document;
global.window = dom.window;

// bridge.js boots itself at its end; keep only loadWASM
const src = readFileSync('dist/pwa/bridge.js', 'utf-8');
const boot = src.lastIndexOf("\nconst root = document.getElementById('bats-root');");
if (boot < 0) throw new Error('bridge.js: boot code not found');
const tmp = join(tmpdir(), `bridge-idb-${process.pid}.mjs`);
writeFileSync(tmp, src.slice(0, boot) + '\n');
const { loadWASM } = await import(tmp);
unlinkSync(tmp);
const wasm = readFileSync('dist/pwa/app.wasm');

// ---- the script's commands
const PUT = 1, GET = 2, DELETE = 3, KEYS = 4, PREFIX = 5, WRITE_ALL = 6,
  INCREMENT = 7, KEEP = 8, SET = 9, BATCH = 10;
const names = { 1: 'put', 2: 'get', 3: 'delete', 4: 'keys', 5: 'prefix', 6: 'write_all',
  7: 'increment', 8: 'update-keep', 9: 'update-set', 10: 'update-batch' };
const encoder = new TextEncoder();
const bytesOf = x => (typeof x === 'string' ? encoder.encode(x) : x === undefined ? new Uint8Array(0) : x);
const op = (command, key, data) => [command, bytesOf(key), bytesOf(data)];

function scriptOf(ops) {
  const parts = [];
  for (const [command, key, data] of ops) {
    const head = new DataView(new ArrayBuffer(3));
    head.setUint8(0, command); head.setUint16(1, key.length, true);
    const mid = new DataView(new ArrayBuffer(4));
    mid.setUint32(0, data.length, true);
    parts.push(new Uint8Array(head.buffer), key, new Uint8Array(mid.buffer), data);
  }
  const all = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { all.set(p, at); at += p.length; }
  return all;
}

// a batch for write_all
const batchPut = (key, value) => {
  const k = bytesOf(key), v = bytesOf(value);
  const out = new DataView(new ArrayBuffer(1 + 2 + k.length + 4 + v.length));
  out.setUint8(0, 1); out.setUint16(1, k.length, true);
  new Uint8Array(out.buffer).set(k, 3);
  out.setUint32(3 + k.length, v.length, true);
  new Uint8Array(out.buffer).set(v, 7 + k.length);
  return new Uint8Array(out.buffer);
};
const batchDelete = key => {
  const k = bytesOf(key);
  const out = new DataView(new ArrayBuffer(3 + k.length));
  out.setUint8(0, 2); out.setUint16(1, k.length, true);
  new Uint8Array(out.buffer).set(k, 3);
  return new Uint8Array(out.buffer);
};
const concat = (...parts) => {
  const all = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { all.set(p, at); at += p.length; }
  return all;
};

// ---- what a report says
const tagNames = {
  0: 'absent', 1: 'found', 2: 'unreadable (no database)', 3: 'unreadable (read failed)',
  4: 'unreadable (unexpected: unknown code)', 5: 'unreadable (unexpected: unclaimed handle)',
  10: 'stored', 11: 'not stored (no database)', 12: 'not stored (aborted)', 13: 'not stored (bad batch)',
  14: 'not stored (unexpected: unknown code)',
  20: 'updated', 21: 'kept as read', 22: 'update unreadable (no database)',
  23: 'update unreadable (read failed)', 24: 'update unreadable (unexpected: unknown code)',
  25: 'update unreadable (unexpected: unclaimed handle)', 26: 'not updated (no database)',
  27: 'not updated (aborted)', 28: 'not updated (bad batch)', 29: 'not updated (unexpected: unknown code)',
};
const show = bytes => {
  const text = new TextDecoder().decode(bytes);
  return /^[\x20-\x7e]*$/.test(text) ? JSON.stringify(text)
    : [...bytes].map(b => b.toString(16).padStart(2, '0')).join(' ');
};
const withCode = tag => tag % 100 === 4 || tag % 100 === 5 || tag === 14 || tag === 24 || tag === 25 || tag === 29;
function describe(report) {
  const tag = report.tag % 100;
  const seen = report.tag >= 100 ? 'the closure was given: ' : '';
  const name = tagNames[tag];
  if (name === undefined) return `${seen}UNKNOWN TAG ${report.tag}`;
  if (tag === 1) return `${seen}found ${show(report.data)}`;
  if (withCode(report.tag >= 100 ? tag : report.tag)) return `${seen}${name} ${report.number}`;
  return `${seen}${name}`;
}

// ---- a session: one wasm app on a fresh IndexedDB
const out = [];
const print = line => { out.push(line); console.log(line); };

async function session(name, body) {
  globalThis.indexedDB = new IDBFactory();
  const reports = [];
  let script = new Uint8Array(0);
  let loaded;
  const root = document.getElementById('bats-root');
  loaded = await loadWASM(wasm, root, { extraImports: {
    test_script(ptr, cap) {
      new Uint8Array(loaded.exports.memory.buffer, ptr, script.length).set(script);
      return script.length;
    },
    test_report(index, tag, number, ptr, len) {
      const data = len > 0 ? new Uint8Array(loaded.exports.memory.buffer, ptr, len).slice() : new Uint8Array(0);
      reports.push({ index, tag, number, data });
    },
  } });
  print(`== ${name}`);
  let runs = 0;
  const api = {
    exports: loaded.exports,
    reports,
    // starts the commands together; waits for each one's outcome
    async run(ops, { wait = true } = {}) {
      runs++;
      const first = reports.length;
      script = scriptOf(ops);
      loaded.exports.test_run();
      if (wait) await api.settled(first, ops.length, `run ${runs}`);
      return reports.slice(first);
    },
    async settled(first, count, label) {
      const finals = () => reports.slice(first).filter(r => r.tag < 100).length;
      for (let tries = 0; finals() < count && tries < 500; tries++) await new Promise(r => setTimeout(r, 10));
      if (finals() !== count) print(`  ${label}: ${finals()} of ${count} commands answered`);
      await new Promise(r => setTimeout(r, 50)); // nothing answers twice
      if (finals() !== count) print(`  ${label}: ${finals()} outcomes for ${count} commands`);
    },
    // prints a run's reports, by command, what the closure was given first
    say(ops, got, label = `run`) {
      const sorted = [...got].sort((a, b) => a.index - b.index || (b.tag >= 100) - (a.tag >= 100));
      for (const r of sorted) print(`  ${label} #${r.index} ${names[ops[r.index][0]]} ${show(ops[r.index][1])}: ${describe(r)}`);
    },
    async go(label, ops) { const got = await api.run(ops); api.say(ops, got, label); return got; },
  };
  await body(api);
}

// ---- patches of fake-indexeddb, undone after each scenario
const originals = {
  get: IDBObjectStore.prototype.get,
  put: IDBObjectStore.prototype.put,
};
let putCalls = 0;
function patched() {
  IDBObjectStore.prototype.put = function (value, key) {
    putCalls++;
    if (key === 'quota') { this.transaction.abort(); return {}; } // storage full
    return originals.put.call(this, value, key);
  };
  // a read that fails: the request errors and its transaction aborts
  IDBObjectStore.prototype.get = function (key) {
    if (key !== 'bad') return originals.get.call(this, key);
    const request = {};
    const tx = this.transaction;
    setTimeout(() => { request.onerror && request.onerror(); try { tx.abort(); } catch (e) {} });
    return request;
  };
}
function unpatched() {
  IDBObjectStore.prototype.put = originals.put;
  IDBObjectStore.prototype.get = originals.get;
}
// indexedDB.open that fails the first `failures` times, or never answers
function openFails(failures) {
  const factory = globalThis.indexedDB;
  const real = factory.open.bind(factory);
  const calls = { count: 0 };
  factory.open = (...args) => {
    calls.count++;
    if (calls.count > failures) return real(...args);
    const request = {};
    setTimeout(() => { request.error = new Error('blocked'); request.onerror && request.onerror(); });
    return request;
  };
  return calls;
}
function openHangs() {
  globalThis.indexedDB.open = () => ({});
}
// what is stored under the key, read around the bridge and the patches
async function stored(key) {
  const db = await new Promise((resolve, reject) => {
    const request = globalThis.indexedDB.open('bats', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('kv');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  const value = await new Promise((resolve, reject) => {
    const request = originals.get.call(db.transaction('kv', 'readonly').objectStore('kv'), key);
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  db.close();
  return value === undefined ? 'nothing' : show(new Uint8Array(value));
}
const count = bytes => new DataView(bytes.buffer, bytes.byteOffset, 4).getUint32(0, true);

// ---- the scenarios
patched();

await session('put, get, delete and list keys unchanged', async s => {
  await s.go('run 1', [op(PUT, 'k1', 'v1'), op(PUT, 'k2', 'value two')]);
  await s.go('run 2', [op(GET, 'k1'), op(GET, 'k3'), op(KEYS, 'k')]);
  await s.go('run 3', [op(DELETE, 'k1')]);
  await s.go('run 4', [op(GET, 'k1'), op(GET, 'k2')]);
});

await session('a failed open is forgotten', async s => {
  const calls = openFails(1);
  await s.go('run 1', [op(GET, 'a'), op(PUT, 'a', 'one')]);
  print(`  opens so far: ${calls.count}`);
  await s.go('run 2', [op(PUT, 'a', 'one')]);
  print(`  opens so far: ${calls.count}`);
  await s.go('run 3', [op(GET, 'a')]);
  print(`  opens in all: ${calls.count}`);
});

await session('a database that cannot be opened, for every call', async s => {
  openFails(1);
  await s.go('run 1', [op(GET, 'a'), op(PUT, 'a', 'one'), op(DELETE, 'a'), op(KEYS, 'a'),
    op(PREFIX, 'a'), op(WRITE_ALL, '', batchPut('a', 'one')), op(SET, 'a', 'two')]);
});

await session('a request or transaction that fails', async s => {
  await s.go('run 1', [op(PUT, 'good', 'g')]);
  await s.go('run 2', [op(GET, 'bad'), op(PUT, 'bad', 'x'), op(PUT, 'quota', 'x'), op(GET, 'good')]);
});

await session('codes bridge does not recognise', async s => {
  openHangs();
  // none of these is answered by JS: each is the resolver of its number
  const ops = [op(GET, 'x'), op(GET, 'y'), op(PUT, 'z', 'v'), op(DELETE, 'w'), op(SET, 'u', 'v'),
    op(KEYS, 'p'), op(PREFIX, 'q'), op(WRITE_ALL, '', batchPut('a', 'b')), op(GET, 'm')];
  const got = await s.run(ops, { wait: false });
  const e = s.exports;
  e.bats_idb_fire_get(0, -9);
  e.bats_idb_fire_get(1, 777);
  e.bats_idb_fire(2, -9);
  e.bats_idb_fire(3, -3);
  e.bats_idb_update_done(4, -9);
  e.bats_idb_fire_get(5, -1);
  e.bats_idb_fire_get(6, -2);
  e.bats_idb_fire(7, -2);
  e.bats_idb_fire_get(8, 0);
  await s.settled(0, ops.length, 'run 1');
  s.say(ops, s.reports, 'run 1');
  // a resolver fired twice answers once
  e.bats_idb_fire_get(0, 0);
  await new Promise(r => setTimeout(r, 50));
  print(`  reports after a second fire: ${s.reports.length}`);
});

await session('get_prefix', async s => {
  await s.go('run 1', [op(PUT, 'a', 'A'), op(PUT, 'a/1', 'one'), op(PUT, 'a/2', 'two'), op(PUT, 'ab/1', 'X'),
    op(PUT, 'a￿z', 'edge'), op(PUT, 'b/1', 'B'), op(PUT, '￿', 'top'), op(PUT, '￿q', 'top2'),
    op(PUT, 'é/1', 'accent')]);
  for (const prefix of ['a/', 'a', 'b', '￿', 'é', 'zz', 'a/3', '']) {
    const ops = [op(PREFIX, prefix || 'a', undefined)];
    if (prefix === '') continue;
    const got = await s.run(ops);
    const r = got[0];
    if (r.tag !== 1) { s.say(ops, got, `prefix ${JSON.stringify(prefix)}`); continue; }
    const view = new DataView(r.data.buffer, r.data.byteOffset, r.data.length);
    const entries = [];
    for (let at = 0; at < r.data.length;) {
      const keyLen = view.getUint16(at, true); at += 2;
      const key = new TextDecoder().decode(r.data.subarray(at, at + keyLen)); at += keyLen;
      const valueLen = view.getUint32(at, true); at += 4;
      const value = new TextDecoder().decode(r.data.subarray(at, at + valueLen)); at += valueLen;
      entries.push(`${JSON.stringify(key)}=${JSON.stringify(value)}`);
    }
    print(`  prefix ${JSON.stringify(prefix)}: ${r.data.length} bytes, ${entries.join(' ')}`);
    if (prefix === 'a/') print(`  its layout: ${[...r.data].map(b => b.toString(16).padStart(2, '0')).join(' ')}`);
  }
});

await session('write_all', async s => {
  await s.go('setup', [op(PUT, 'old', 'gone soon'), op(PUT, 'keep', 'kept')]);
  // three puts and a delete: all four apply
  await s.go('batch', [op(WRITE_ALL, '', concat(batchPut('n1', 'one'), batchPut('n2', 'two'),
    batchDelete('old'), batchPut('n3', 'three')))]);
  await s.go('after', [op(GET, 'n1'), op(GET, 'n2'), op(GET, 'n3'), op(GET, 'old'), op(GET, 'keep')]);
  // malformed: nothing of the batch is written, whatever its good part
  const good = batchPut('m1', 'must not be written');
  const cases = {
    'a value length past the end': concat(good, batchPut('m2', 'xxxx').subarray(0, 9)),
    'a key length past the end': concat(good, new Uint8Array([1, 200, 0, 97])),
    'an op that is neither put nor delete': concat(good, new Uint8Array([3, 1, 0, 97])),
    'an op that is zero': concat(good, new Uint8Array([0, 1, 0, 97])),
    'a header cut short': concat(good, new Uint8Array([1, 1])),
    'a missing value length': concat(good, new Uint8Array([1, 1, 0, 97, 1, 0])),
    'an empty key': concat(good, new Uint8Array([2, 0, 0])),
    'a key that is not UTF-8': concat(good, new Uint8Array([2, 2, 0, 0xc3, 0x28])),
    'a value length of 4 GiB': concat(good, new Uint8Array([1, 1, 0, 97, 255, 255, 255, 255, 1])),
  };
  for (const [what, batch] of Object.entries(cases)) {
    const ops = [op(WRITE_ALL, '', batch)];
    const got = await s.run(ops);
    print(`  ${what}: ${describe(got[0])}; m1 is ${await stored('m1')}`);
  }
  // a transaction that aborts part way takes all of it back
  const ops = [op(WRITE_ALL, '', concat(batchPut('p1', 'x'), batchPut('quota', 'x'), batchPut('p2', 'x'),
    batchDelete('keep')))];
  const got = await s.run(ops);
  print(`  abort part way: ${describe(got[0])}; p1 is ${await stored('p1')}, keep is ${await stored('keep')}`);
  // two batches together, then a later one: in order
  await s.go('together', [op(WRITE_ALL, '', concat(batchPut('t', 'first'), batchPut('t', 'second'))),
    op(WRITE_ALL, '', batchPut('t', 'third'))]);
  print(`  t is ${await stored('t')}`);
});

await session('update', async s => {
  // fifty at once, on a key that is not there: each reads what the one before wrote
  const increments = Array.from({ length: 50 }, () => op(INCREMENT, 'counter'));
  const got = await s.run(increments);
  const outcomes = {};
  for (const r of got) outcomes[describe(r)] = (outcomes[describe(r)] || 0) + 1;
  print(`  50 increments: ${JSON.stringify(outcomes)}`);
  const read = await s.run([op(GET, 'counter')]);
  print(`  counter is ${count(read[0].data)}`);
  // increments mixed with a delete and a put of the same key, in order
  await s.go('mixed', [op(INCREMENT, 'counter'), op(INCREMENT, 'counter'), op(DELETE, 'counter'),
    op(INCREMENT, 'counter')]);
  const again = await s.run([op(GET, 'counter')]);
  print(`  counter is ${count(again[0].data)}`);

  // an absent key: the closure is given Absent, and what it answers is put
  await s.go('absent', [op(SET, 'fresh', 'made')]);
  print(`  fresh is ${await stored('fresh')}`);
  // keeping: nothing written, on a key that is there and on one that is not
  await s.go('keep', [op(KEEP, 'fresh'), op(KEEP, 'never')]);
  print(`  fresh is ${await stored('fresh')}, never is ${await stored('never')}`);
  // set over what is there: the closure is given what is there
  await s.go('set', [op(SET, 'fresh', 'remade')]);
  print(`  fresh is ${await stored('fresh')}`);

  // a read that fails: the closure is told, and nothing is ever written
  const before = putCalls;
  await s.go('unreadable', [op(SET, 'bad', 'overwritten')]);
  print(`  puts made: ${putCalls - before}; bad is ${await stored('bad')}`);
  // a transaction that aborts after the put: the old value stays
  await s.go('seed', [op(SET, 'old', 'x')]);
  await s.go('abort', [op(SET, 'quota', 'new')]);
  print(`  quota is ${await stored('quota')}`);
  const seeded = await s.run([op(PUT, 'other', 'v1')]);
  // an abort of the update of a key that is there
  const aborted = [op(SET, 'quota', 'new')];
  await s.go('abort again', aborted);
  print(`  other is ${await stored('other')}`);
});

await session('an abort of an update leaves the old value', async s => {
  // put the old value around the patch, then update it under the patch
  unpatched();
  await s.go('seed', [op(PUT, 'quota', 'old')]);
  patched();
  await s.go('update', [op(SET, 'quota', 'new')]);
  print(`  quota is ${await stored('quota')}`);
});

await session('an update whose database never opens', async s => {
  const calls = openFails(1);
  await s.go('run 1', [op(SET, 'a', 'one'), op(INCREMENT, 'a')]);
  await s.go('run 2', [op(INCREMENT, 'a')]);
  print(`  a is ${await stored('a')}; opens: ${calls.count}`);
});

await session('update with a batch', async s => {
  await s.go('seed', [op(PUT, 'rec', 'damaged'), op(PUT, 'other', 'untouched')]);
  // the record repaired and a copy of the old bytes under another key: together
  await s.go('repair', [op(BATCH, 'rec', concat(batchPut('rec', 'repaired'), batchPut('quarantine/rec', 'damaged')))]);
  print(`  rec is ${await stored('rec')}, quarantine/rec is ${await stored('quarantine/rec')}`);
  // a batch that does not name the key, and one that deletes
  await s.go('elsewhere', [op(BATCH, 'rec', concat(batchPut('x', 'y'), batchDelete('other')))]);
  print(`  rec is ${await stored('rec')}, x is ${await stored('x')}, other is ${await stored('other')}`);
  // malformed: nothing of it is written, the transaction aborts
  const good = batchPut('rec', 'must not be written');
  await s.go('malformed', [op(BATCH, 'rec', concat(good, batchPut('q', 'zz').subarray(0, 8)))]);
  print(`  rec is ${await stored('rec')}, q is ${await stored('q')}`);
  await s.go('bad op', [op(BATCH, 'rec', concat(good, new Uint8Array([7, 1, 0, 97])))]);
  print(`  rec is ${await stored('rec')}`);
  // a transaction that aborts part way takes the whole batch back
  await s.go('abort', [op(BATCH, 'rec', concat(batchPut('rec', 'half'), batchPut('quota', 'x')))]);
  print(`  rec is ${await stored('rec')}, quota is ${await stored('quota')}`);
  // an unreadable key: the closure runs, its batch is dropped
  const before = putCalls;
  await s.go('unreadable', [op(BATCH, 'bad', batchPut('quarantine/bad', 'copy'))]);
  print(`  puts made: ${putCalls - before}; quarantine/bad is ${await stored('quarantine/bad')}`);
});

unpatched();
process.exit(0);
