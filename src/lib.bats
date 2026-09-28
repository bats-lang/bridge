(* bridge -- centralized WASM host import wrappers for bats *)
(* No other package touches $UNSAFE or declares extern WASM imports. *)
(* Bridge exports safe #pub fun wrappers over all mac# host calls. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use promise as P
#use result as R

staload "./js_emitter.bats"
staload "./stash.bats"
staload "./decompress.bats"
staload "./event.bats"
staload "./file.bats"
staload "./blob.bats"
staload "./clipboard.bats"
staload "./dom.bats"
staload "./dom_read.bats"
staload "./fetch.bats"
staload "./idb.bats"
staload "./media.bats"
staload "./nav.bats"
staload "./notify.bats"
staload "./scroll.bats"
staload "./timer.bats"
staload "./window.bats"
staload "./xml.bats"

(* ============================================================
   C runtime -- measure, listener tables + WASM exports
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{$
/* Measure stash -- 6 slots for x, y, w, h, scrollW, scrollH */
#define _BRIDGE_MEASURE_SLOTS 6
static int _bridge_measure[_BRIDGE_MEASURE_SLOTS] = {0};

void bats_measure_set(int slot, int v) {
  if (slot >= 0 && slot < _BRIDGE_MEASURE_SLOTS) _bridge_measure[slot] = v;
}

int bats_bridge_measure_get(int slot) {
  if (slot >= 0 && slot < _BRIDGE_MEASURE_SLOTS) return _bridge_measure[slot];
  return 0;
}

/* Listener table -- max 128 */
#define _BRIDGE_MAX_LISTENERS 128
static void *_bridge_listener_table[_BRIDGE_MAX_LISTENERS] = {0};

void bats_listener_set(int id, void *cb) {
  if (id >= 0 && id < _BRIDGE_MAX_LISTENERS) _bridge_listener_table[id] = cb;
}

void *bats_listener_get(int id) {
  if (id >= 0 && id < _BRIDGE_MAX_LISTENERS) return _bridge_listener_table[id];
  return (void*)0;
}

/* The popstate callback -- one, set by set_popstate_callback */
static void *_bridge_popstate_cb = (void*)0;

void bats_popstate_set(void *cb) { _bridge_popstate_cb = cb; }

void *bats_popstate_get(void) { return _bridge_popstate_cb; }
%}
end
end (* #target wasm *)

(* ============================================================
   produce_bridge -- returns the complete JS bridge as a string
   ============================================================ *)

#pub fun produce_bridge {n:nat | n + 51900 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 51900] $B.builder(m)): void

#pub fun produce_bridge_app {nw:nat | nw < 200}{nr:nat | nr < 100}{n:nat | n + 53900 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 53900] $B.builder(m),
   wasm_name: string nw, root_id: string nr): void

(* The service worker: the shell is cached when it is installed, and
   every same-origin GET goes to the network first (so a new build is
   used as soon as it is served), its response kept in the cache for
   when there is no network *)
#pub fun produce_service_worker {nw:nat | nw < 200}{n:nat | n + 1400 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 1400] $B.builder(m),
   wasm_name: string nw): void

implement produce_bridge(b) = emit_js_all(b)

(* The page's loader: the wasm is fetched and run, and the service
   worker registered. The wasm's ETag (or Last-Modified) when the page
   loaded is its build's stamp: while the page is shown it is asked for
   again every 30 seconds, and whenever the page is shown again, and
   when a new build has been served in the meantime the page reloads
   itself onto it. A server that gives neither header is never asked. *)
fn _produce_app_tail {nw:nat | nw < 200}{nr:nat | nr < 100}{n:nat | n + 2000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2000] $B.builder(m),
   wasm_name: string nw, root_id: string nr): void = let
  val () = $B.bput(b, "\nconst root = document.getElementById('")
  val () = $B.bput(b, root_id)
  val () = $B.bput(b, "');\n")
  val () = $B.bput(b, "const batsWasmName = '")
  val () = $B.bput(b, wasm_name)
  val () = $B.bput(b, "';\n")
  val () = $B.bput(b, "async function batsBuildStamp() {\n")
  val () = $B.bput(b, "  try {\n")
  val () = $B.bput(b, "    const r = await fetch(batsWasmName, { method: 'HEAD', cache: 'no-store' });\n")
  val () = $B.bput(b, "    if (!r.ok) return null;\n")
  val () = $B.bput(b, "    return r.headers.get('etag') || r.headers.get('last-modified');\n")
  val () = $B.bput(b, "  } catch (e) { return null; }\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "const batsStampAtLoad = batsBuildStamp();\n")
  val () = $B.bput(b, "const resp = await fetch(batsWasmName);\n")
  val () = $B.bput(b, "const bytes = await resp.arrayBuffer();\n")
  val () = $B.bput(b, "await loadWASM(bytes, root, {});\n")
  val () = $B.bput(b, "if ('serviceWorker' in navigator) {\n")
  val () = $B.bput(b, "  navigator.serviceWorker.register('service-worker.js');\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "batsStampAtLoad.then(stamp => {\n")
  val () = $B.bput(b, "  if (!stamp) return;\n")
  val () = $B.bput(b, "  let reloading = false;\n")
  val () = $B.bput(b, "  const check = async () => {\n")
  val () = $B.bput(b, "    if (reloading || document.visibilityState !== 'visible') return;\n")
  val () = $B.bput(b, "    const now = await batsBuildStamp();\n")
  val () = $B.bput(b, "    if (now && now !== stamp) { reloading = true; location.reload(); }\n")
  val () = $B.bput(b, "  };\n")
  val () = $B.bput(b, "  setInterval(check, 30000);\n")
  val () = $B.bput(b, "  document.addEventListener('visibilitychange', check);\n")
  val () = $B.bput(b, "});\n")
in end

implement produce_bridge_app (b, wasm_name, root_id) = let
  val () = emit_js_all(b)
  val () = _produce_app_tail(b, wasm_name, root_id)
in end

implement produce_service_worker (b, wasm_name) = let
  val () = $B.bput(b, "const SHELL = [\n")
  val () = $B.bput(b, "  './', '")
  val () = $B.bput(b, wasm_name)
  val () = $B.bput(b, "', 'bridge.js', 'manifest.json',\n")
  val () = $B.bput(b, "];\n")
  val () = $B.bput(b, "const CACHE = 'bats-pwa-' + btoa(SHELL.join(',')).slice(0,8);\n\n")
  val () = $B.bput(b, "self.addEventListener('install', e => {\n")
  val () = $B.bput(b, "  self.skipWaiting();\n")
  val () = $B.bput(b, "  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));\n")
  val () = $B.bput(b, "});\n\n")
  val () = $B.bput(b, "self.addEventListener('activate', e => {\n")
  val () = $B.bput(b, "  e.waitUntil(\n")
  val () = $B.bput(b, "    caches.keys().then(keys =>\n")
  val () = $B.bput(b, "      Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))\n")
  val () = $B.bput(b, "    ).then(() => self.clients.claim())\n")
  val () = $B.bput(b, "  );\n")
  val () = $B.bput(b, "});\n\n")
  (* Network first, so a new build is taken as soon as it is served;
     what was fetched is kept for when there is no network *)
  val () = $B.bput(b, "self.addEventListener('fetch', e => {\n")
  val () = $B.bput(b, "  const r = e.request;\n")
  (* A file the host hands over (Capacitor's /_capacitor_file_ URLs) is
     the host's to serve, and is not kept *)
  val () = $B.bput(b, "  const u = new URL(r.url);\n")
  val () = $B.bput(b, "  if (r.method !== 'GET' || u.origin !== self.location.origin || u.pathname.startsWith('/_capacitor_')) return;\n")
  val () = $B.bput(b, "  e.respondWith(fetch(r).then(res => {\n")
  val () = $B.bput(b, "    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(r, copy)); }\n")
  val () = $B.bput(b, "    return res;\n")
  val () = $B.bput(b, "  }).catch(() => caches.match(r).then(m => m || caches.match('./'))));\n")
  val () = $B.bput(b, "});\n")
in end
