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
staload "./plugins.bats"
staload "./google_account.bats"
staload "./backup_file.bats"
staload "./stash.bats"
staload "./decompress.bats"
staload "./event.bats"
staload "./file.bats"
staload "./external.bats"
staload "./blob.bats"
staload "./clipboard.bats"
staload "./dom.bats"
staload "./dom_read.bats"
staload "./fetch.bats"
staload "./idb.bats"
staload "./audio.bats"
staload "./media.bats"
staload "./nav.bats"
staload "./build_watch.bats"
staload "./notify.bats"
staload "./random.bats"
staload "./scroll.bats"
staload "./screen.bats"
staload "./share.bats"
staload "./speech.bats"
staload "./storage.bats"
staload "./app.bats"
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

/* Closures let go. A listener is a linear closure (lincloptr1, made
   with llam), freed as cloptr_free frees one when its slot is set
   again or unlistened. A listener may be let go while one is running
   (its own unlisten, inside its callback): then it is only retired,
   and freed once the outermost listener has returned, so no listener
   runs on freed memory. */
static int _bridge_running = 0;
static void **_bridge_retired = 0;
static int _bridge_retired_count = 0;
static int _bridge_retired_cap = 0;

static void _bridge_closure_let_go(void *closure) {
  if (!closure) return;
  if (_bridge_running == 0) { atspre_cloptr_free(closure); return; }
  if (_bridge_retired_count == _bridge_retired_cap) {
    int cap = _bridge_retired_cap ? 2 * _bridge_retired_cap : 16;
    void **grown = (void **)malloc(cap * (int)sizeof(void *));
    if (_bridge_retired_cap) {
      memcpy(grown, _bridge_retired, _bridge_retired_cap * sizeof(void *));
      free(_bridge_retired);
    }
    _bridge_retired = grown;
    _bridge_retired_cap = cap;
  }
  _bridge_retired[_bridge_retired_count++] = closure;
}

/* Around each call of a listener: the closures retired while it ran
   are freed when the outermost one returns */
void bats_listener_enter(void) { _bridge_running++; }

void bats_listener_leave(void) {
  int i;
  _bridge_running--;
  if (_bridge_running > 0) return;
  for (i = 0; i < _bridge_retired_count; i++) atspre_cloptr_free(_bridge_retired[i]);
  _bridge_retired_count = 0;
}

/* Listener table -- max 128. A slot holds the closure on_event calls
   and, for a listener bridge decodes for, the caller's closure, which
   the decoder calls (held here so that it is freed with the slot). */
#define _BRIDGE_MAX_LISTENERS 128
static void *_bridge_listener_table[_BRIDGE_MAX_LISTENERS] = {0};
static void *_bridge_listener_inner[_BRIDGE_MAX_LISTENERS] = {0};

/* Sets slot id to cb (null: empties it), letting go of what it held */
void bats_listener_set(int id, void *cb) {
  if (id >= 0 && id < _BRIDGE_MAX_LISTENERS) {
    _bridge_closure_let_go(_bridge_listener_table[id]);
    _bridge_closure_let_go(_bridge_listener_inner[id]);
    _bridge_listener_table[id] = cb;
    _bridge_listener_inner[id] = (void*)0;
  }
}

/* Sets slot id to a decoder and the caller's closure it calls */
void bats_listener_set_decoded(int id, void *decoder, void *inner) {
  if (id >= 0 && id < _BRIDGE_MAX_LISTENERS) {
    bats_listener_set(id, decoder);
    _bridge_listener_inner[id] = inner;
  }
}

void *bats_listener_get(int id) {
  if (id >= 0 && id < _BRIDGE_MAX_LISTENERS) return _bridge_listener_table[id];
  return (void*)0;
}

/* The popstate callback -- one, set by set_popstate_callback, which
   lets go of the one before */
static void *_bridge_popstate_cb = (void*)0;

void bats_popstate_set(void *cb) {
  _bridge_closure_let_go(_bridge_popstate_cb);
  _bridge_popstate_cb = cb;
}

void *bats_popstate_get(void) { return _bridge_popstate_cb; }
%}
end
end (* #target wasm *)

(* ============================================================
   produce_bridge -- returns the complete JS bridge as a string
   ============================================================ *)

#pub fun produce_bridge {n:nat | n + 102600 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 102600] $B.builder(m)): void

#pub fun produce_bridge_app {nw:nat | nw < 200}{nr:nat | nr < 100}{n:nat | n + 104600 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 104600] $B.builder(m),
   wasm_name: string nw, root_id: string nr): void

(* The service worker: the shell is cached when it is installed, and
   every same-origin GET of a file directly in its scope goes to the
   network first (so a new build is used as soon as it is served), its
   response kept in the cache for when there is no network. A GET of a
   path in a subdirectory of the scope, or outside it, is not the app's
   (pwa writes the app flat): the worker leaves it to the network and
   keeps nothing of it, so pages published beside the app (a home page,
   a privacy policy) are always the server's. A file shared with the installed app (a
   manifest's share_target: a multipart POST of the field file to
   share-target) is kept in the cache bats-shared and the app opened at
   ?shared=, where the bridge hands it to the app as an external file
   (external_next, in external.bats) *)
#pub fun produce_service_worker {nw:nat | nw < 200}{n:nat | n + 2600 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2600] $B.builder(m),
   wasm_name: string nw): void

(* The Capacitor plugins the atoms use (plugins.bats), each as a
   package.json dependency line after indent, all but the last ending in
   a comma: what the native app installs, so it has every plugin an atom
   may call *)
#pub fun produce_plugin_dependencies {n:nat | n + 640 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 640] $B.builder(m),
   indent: [s:nat | s <= 4] string s): void

implement produce_plugin_dependencies (b, indent) = put_plugin_dependencies(b, indent)

(* The Kotlin standard library's version the native app needs for the
   plugins (plugins.bats): the newest any of them is compiled with *)
#pub fun produce_kotlin_version (): [s:pos | s <= 16] string s

implement produce_kotlin_version () = plugins_kotlin()

(* The app manifest's backup rules: Android's Auto Backup keeps the
   directory of backed-up files (backup_file.bats) and nothing else of
   the app's. For android:fullBackupContent (Android 11 and lower) *)
#pub fun produce_full_backup_content {n:nat | n + 200 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 200] $B.builder(m)): void

implement produce_full_backup_content (b) = put_full_backup_content(b)

(* The same, for android:dataExtractionRules (Android 12 and higher) *)
#pub fun produce_data_extraction_rules {n:nat | n + 400 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 400] $B.builder(m)): void

implement produce_data_extraction_rules (b) = put_data_extraction_rules(b)

implement produce_bridge(b) = emit_js_all(b)

(* The page's loader: the wasm is fetched and run, and the service
   worker registered. Whether a new build is served, and when to load
   it, is the app's (build_watch, build_watch.bats).

   A load that fails (no network and nothing cached, a server error, a
   damaged file) is the one failure JS must handle itself, since no wasm
   runs to say it: the root is replaced by a plain message, in an alert,
   and a Try again button that reloads, and the error is logged. A load
   cut short because the page is going away (a reload, a navigation:
   pagehide) shows nothing *)
fn _produce_app_tail {nw:nat | nw < 200}{nr:nat | nr < 100}{n:nat | n + 2000 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 2000] $B.builder(m),
   wasm_name: string nw, root_id: string nr): void = let
  val () = $B.bput(b, "\nconst root = document.getElementById('")
  val () = $B.bput(b, root_id)
  val () = $B.bput(b, "');\n")
  val () = $B.bput(b, "const batsWasmName = '")
  val () = $B.bput(b, wasm_name)
  val () = $B.bput(b, "';\n")
  val () = $B.bput(b, "let batsLeaving = false;\n")
  val () = $B.bput(b, "window.addEventListener('pagehide', () => { batsLeaving = true; });\n")
  val () = $B.bput(b, "try {\n")
  val () = $B.bput(b, "  const resp = await fetch(batsWasmName);\n")
  val () = $B.bput(b, "  if (!resp.ok) throw new Error(batsWasmName + ': HTTP ' + resp.status);\n")
  val () = $B.bput(b, "  await loadWASM(await resp.arrayBuffer(), root, {});\n")
  val () = $B.bput(b, "} catch (e) {\n")
  val () = $B.bput(b, "  if (!batsLeaving && !(e && e.name === 'AbortError')) {\n")
  val () = $B.bput(b, "    console.error(e);\n")
  val () = $B.bput(b, "    const said = document.createElement('p');\n")
  val () = $B.bput(b, "    said.setAttribute('role', 'alert');\n")
  val () = $B.bput(b, "    said.textContent = 'The app could not be loaded. Check your connection and try again.';\n")
  val () = $B.bput(b, "    const again = document.createElement('button');\n")
  val () = $B.bput(b, "    again.textContent = 'Try again';\n")
  val () = $B.bput(b, "    again.addEventListener('click', () => location.reload());\n")
  val () = $B.bput(b, "    root.replaceChildren(said, again);\n")
  val () = $B.bput(b, "  }\n")
  val () = $B.bput(b, "}\n")
  val () = $B.bput(b, "if ('serviceWorker' in navigator) {\n")
  val () = $B.bput(b, "  navigator.serviceWorker.register('service-worker.js');\n")
  val () = $B.bput(b, "}\n")
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
  val () = $B.bput(b, "const CACHE = 'bats-pwa-' + btoa(SHELL.join(',')).slice(0,8);\n")
  val () = $B.bput(b, "const SHARED = 'bats-shared';\n\n")
  val () = $B.bput(b, "self.addEventListener('install', e => {\n")
  val () = $B.bput(b, "  self.skipWaiting();\n")
  val () = $B.bput(b, "  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)));\n")
  val () = $B.bput(b, "});\n\n")
  val () = $B.bput(b, "self.addEventListener('activate', e => {\n")
  val () = $B.bput(b, "  e.waitUntil(\n")
  val () = $B.bput(b, "    caches.keys().then(keys =>\n")
  val () = $B.bput(b, "      Promise.all(keys.filter(k => k !== CACHE && k !== SHARED).map(k => caches.delete(k)))\n")
  val () = $B.bput(b, "    ).then(() => self.clients.claim())\n")
  val () = $B.bput(b, "  );\n")
  val () = $B.bput(b, "});\n\n")
  val () = $B.bput(b, "// A file shared with the installed app (the manifest's share_target, a\n")
  val () = $B.bput(b, "// POST of its field file to share-target) is kept in the cache\n")
  val () = $B.bput(b, "// bats-shared, and the app opened at ?shared=, where the bridge hands it\n")
  val () = $B.bput(b, "// to the app as an external file\n")
  val () = $B.bput(b, "self.addEventListener('fetch', e => {\n")
  val () = $B.bput(b, "  const r = e.request;\n")
  val () = $B.bput(b, "  if (r.method !== 'POST' || !/\\/share-target$/.test(new URL(r.url).pathname)) return;\n")
  val () = $B.bput(b, "  const at = p => new URL(p, self.registration.scope).href;\n")
  val () = $B.bput(b, "  e.respondWith((async () => {\n")
  val () = $B.bput(b, "    const files = (await r.formData()).getAll('file').filter(f => typeof f !== 'string');\n")
  val () = $B.bput(b, "    const c = await caches.open(SHARED);\n")
  val () = $B.bput(b, "    await Promise.all(files.map((f, i) => c.put(at('shared/' + i + '/' + encodeURIComponent(f.name)),\n")
  val () = $B.bput(b, "      new Response(f, { headers: { 'content-type': f.type || 'application/octet-stream' } }))));\n")
  val () = $B.bput(b, "    return Response.redirect(at('./?shared=' + files.length), 303);\n")
  val () = $B.bput(b, "  })().catch(() => Response.redirect(at('./'), 303)));\n")
  val () = $B.bput(b, "});\n")
  val () = $B.bput(b, "\n")
  (* Network first, so a new build is taken as soon as it is served;
     what was fetched is kept for when there is no network *)
  val () = $B.bput(b, "self.addEventListener('fetch', e => {\n")
  val () = $B.bput(b, "  const r = e.request;\n")
  (* A file the host hands over (Capacitor's /_capacitor_file_ URLs) is
     the host's to serve, and is not kept. Nor is anything outside the
     app: pwa writes the app flat, every file of it directly in the
     scope, so a path in a subdirectory of the scope (pages published
     beside the app, such as its home page) or outside it is another
     site's, left to the network, neither answered nor kept *)
  val () = $B.bput(b, "  const u = new URL(r.url);\n")
  val () = $B.bput(b, "  if (r.method !== 'GET' || u.origin !== self.location.origin || u.pathname.startsWith('/_capacitor_')) return;\n")
  val () = $B.bput(b, "  const base = new URL(self.registration.scope).pathname;\n")
  val () = $B.bput(b, "  if (!u.pathname.startsWith(base) || u.pathname.slice(base.length).includes('/')) return;\n")
  val () = $B.bput(b, "  e.respondWith(fetch(r).then(res => {\n")
  val () = $B.bput(b, "    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(r, copy)); }\n")
  val () = $B.bput(b, "    return res;\n")
  val () = $B.bput(b, "  }).catch(() => caches.match(r).then(m => m || caches.match('./'))));\n")
  val () = $B.bput(b, "});\n")
in end
