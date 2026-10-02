// Runs dist/pwa/service-worker.js, as pwa generated it, with its scope
// at https://example.org/app/, and sends it GETs: which it answers
// (the app's own files, directly in the scope) and which it leaves to
// the network (a path in a subdirectory of the scope, such as pages
// published beside the app, one outside the scope, another origin's,
// Capacitor's files, and a POST that is not a share).
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const scope = 'https://example.org/app/';
const listeners = { install: [], activate: [], fetch: [] };
const fetched = [];
const cached = [];
const cache = {
  put: async request => { cached.push(new URL(request.url).pathname); },
  addAll: async () => {},
  match: async () => undefined,
  keys: async () => [],
};
const self = {
  location: new URL(scope + 'service-worker.js'),
  registration: { scope },
  addEventListener: (type, f) => listeners[type].push(f),
  skipWaiting: () => {},
  clients: { claim: async () => {} },
};
const context = vm.createContext({
  self, URL, btoa, Promise,
  caches: { open: async () => cache, keys: async () => [], match: async () => undefined, delete: async () => true },
  fetch: async request => { fetched.push(request.url); return { ok: true, clone: () => ({}) }; },
  Response: class { static redirect() { return {}; } },
});
vm.runInContext(readFileSync('dist/pwa/service-worker.js', 'utf-8'), context);

const ask = async (method, url) => {
  let answered = false;
  const request = { method, url };
  const event = { request, respondWith: p => { answered = true; return Promise.resolve(p).catch(() => {}); } };
  for (const f of listeners.fetch) f(event);
  await new Promise(r => setTimeout(r, 10));
  console.log(`${method} ${url}: ${answered ? 'answered' : 'left to the network'}`);
};

await ask('GET', scope);
await ask('GET', scope + '?shared=1');
await ask('GET', scope + 'app.wasm');
await ask('GET', scope + 'icon-192.png');
await ask('GET', scope + 'homepage/');
await ask('GET', scope + 'homepage/privacy.html');
await ask('GET', scope + 'docs/a/b.html');
await ask('GET', 'https://example.org/other.html');
await ask('GET', 'https://example.org/_capacitor_file_/a.epub');
await ask('GET', 'https://elsewhere.example/app/feed.xml');
await ask('POST', scope + 'app.wasm');
console.log(`kept: ${cached.join(' ')}`);
