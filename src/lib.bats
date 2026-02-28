(* bridge -- centralized WASM host import wrappers for bats *)
(* No other package touches $UNSAFE or declares extern WASM imports. *)
(* Bridge exports safe #pub fun wrappers over all mac# host calls. *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use promise as P
#use result as R

(* ============================================================
   C runtime -- stash, measure, listener tables + WASM exports
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{#
#ifndef _BRIDGE_RUNTIME_DEFINED
#define _BRIDGE_RUNTIME_DEFINED
/* Bridge int stash -- 4 slots for stash IDs and metadata */
static int _bridge_stash_int[4] = {0};

void bats_bridge_stash_set_int(int slot, int v) {
  _bridge_stash_int[slot] = v;
}

int bats_bridge_stash_get_int(int slot) {
  return _bridge_stash_int[slot];
}

/* Measure stash -- 6 slots for x, y, w, h, scrollW, scrollH */
static int _bridge_measure[6] = {0};

void bats_measure_set(int slot, int v) {
  _bridge_measure[slot] = v;
}

static int _bridge_measure_get(int slot) {
  return _bridge_measure[slot];
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

/* JS-side data stash read import */
static void _bridge_stash_read(int stash_id, void *dest, int len);
#endif
%}
end
end (* #target wasm *)

(* ============================================================
   Public API -- safe typed wrappers
   ============================================================ *)

(* --- Timer --- *)

#pub fun timer_set
  (delay_ms: int, stash_id: int): void

#pub fun exit(): void

(* --- DOM --- *)

#pub fun dom_flush
  {l:agz}{n:nat}{m:nat | m <= n}
  (buf: !$A.arr(byte, l, n), len: int m): void

#pub fun set_image_src
  {ld:agz}{nd:pos}{lm:agz}{nm:pos}
  (node_id: int,
   data: !$A.borrow(byte, ld, nd), data_len: int nd,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm): void

(* --- DOM read --- *)

#pub fun measure
  (node_id: int): $R.result(int, int)

#pub fun get_measure_x(): int

#pub fun get_measure_y(): int

#pub fun get_measure_w(): int

#pub fun get_measure_h(): int

#pub fun get_measure_scroll_w(): int

#pub fun get_measure_scroll_h(): int

#pub fun query_selector
  {lb:agz}{n:pos}
  (sel: !$A.borrow(byte, lb, n), sel_len: int n): $R.option(int)

(* --- Event --- *)

#pub fun listen
  {lb:agz}{n:pos}
  (node_id: int,
   event_type: !$A.borrow(byte, lb, n), type_len: int n,
   listener_id: int): void

#pub fun unlisten
  (listener_id: int): void

#pub fun prevent_default(): void

#pub fun listener_set
  (id: int, cb: ptr): void

#pub fun listener_set_closure
  (id: int, cb: (int) -<cloref1> int): void

#pub fun listener_clear
  (id: int): void

#pub fun listener_get
  (id: int): ptr

(* --- Navigation --- *)

#pub fun get_url
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): $R.result(int, int)

#pub fun get_hash
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): $R.result(int, int)

#pub fun set_hash
  {lb:agz}{n:nat}
  (hash: !$A.borrow(byte, lb, n), hash_len: int n): void

#pub fun replace_state
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): void

#pub fun push_state
  {lb:agz}{n:nat}
  (url: !$A.borrow(byte, lb, n), url_len: int n): void

(* --- Window --- *)

#pub fun focus(): void

#pub fun get_visibility(): int

#pub fun log
  {lb:agz}{n:nat}
  (level: int, msg: !$A.borrow(byte, lb, n), msg_len: int n): void

(* --- IDB --- *)

#pub fun idb_put
  {lk:agz}{nk:pos}{lv:agz}{nv:nat}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk,
   val_data: !$A.borrow(byte, lv, nv), val_len: int nv,
   stash_id: int): void

#pub fun idb_get
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk,
   stash_id: int): void

#pub fun idb_get_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun idb_delete
  {lk:agz}{nk:pos}
  (key: !$A.borrow(byte, lk, nk), key_len: int nk,
   stash_id: int): void

(* --- Fetch --- *)

#pub fun fetch_req
  {lb:agz}{n:pos}
  (url: !$A.borrow(byte, lb, n), url_len: int n,
   stash_id: int): void

#pub fun fetch_body_len(): int

#pub fun fetch_body
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

(* --- Clipboard --- *)

#pub fun clipboard_write
  {lb:agz}{n:nat}
  (text: !$A.borrow(byte, lb, n), text_len: int n,
   stash_id: int): void

(* --- File --- *)

#pub fun file_open
  (input_node_id: int, stash_id: int): void

#pub fun file_size(): int

#pub fun file_name_len(): int

#pub fun file_name
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun file_read
  {l:agz}{n:pos}
  (handle: int, file_offset: int,
   out: !$A.arr(byte, l, n), len: int n): $R.result(int, int)

#pub fun file_close
  (handle: int): void

(* --- Decompress --- *)

#pub fun decompress_req
  {lb:agz}{n:pos}
  (data: !$A.borrow(byte, lb, n), data_len: int n,
   method: int, stash_id: int): void

#pub fun decompress_len(): int

#pub fun blob_read
  {l:agz}{n:pos}
  (handle: int, blob_offset: int,
   out: !$A.arr(byte, l, n), len: int n): $R.result(int, int)

#pub fun blob_free
  (handle: int): void

(* --- Notify --- *)

#pub fun notify_request
  (stash_id: int): void

#pub fun notify_show
  {lb:agz}{n:pos}
  (title: !$A.borrow(byte, lb, n), title_len: int n): void

#pub fun notify_subscribe
  {lb:agz}{n:pos}
  (vapid: !$A.borrow(byte, lb, n), vapid_len: int n,
   stash_id: int): void

#pub fun notify_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun notify_get_sub
  (stash_id: int): void

(* --- XML --- *)

#pub fun xml_parse
  {lb:agz}{n:pos}
  (html: !$A.borrow(byte, lb, n), len: int n): int

#pub fun xml_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

(* --- Stash --- *)

#pub fun stash_read
  {n:pos | n <= 1048576}
  (stash_id: int, len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun stash_set_int
  (slot: int, v: int): void

#pub fun stash_get_int
  (slot: int): int

(* --- WASM exports -- called by JS host --- *)

#pub fun on_timer_fire
  (resolver_id: int): void = "ext#bats_timer_fire"

#pub fun on_event
  (listener_id: int, payload_len: int): void = "ext#bats_on_event"

#pub fun on_fetch_complete
  (resolver_id: int, status: int, body_len: int): void = "ext#bats_on_fetch_complete"

#pub fun on_clipboard_complete
  (resolver_id: int, success: int): void = "ext#bats_on_clipboard_complete"

#pub fun on_file_open
  (resolver_id: int, handle: int, size: int): void = "ext#bats_on_file_open"

#pub fun on_decompress_complete
  (resolver_id: int, handle: int, decompressed_len: int)
  : void = "ext#bats_on_decompress_complete"

#pub fun on_idb_fire
  (resolver_id: int, status: int): void = "ext#bats_idb_fire"

#pub fun on_idb_fire_get
  (resolver_id: int, data_len: int): void = "ext#bats_idb_fire_get"

#pub fun on_permission_result
  (resolver_id: int, granted: int): void = "ext#bats_on_permission_result"

#pub fun on_push_subscribe
  (resolver_id: int, json_len: int): void = "ext#bats_on_push_subscribe"

(* ============================================================
   produce_bridge -- returns the complete JS bridge as a string
   ============================================================ *)

#pub fun produce_bridge(b: !$B.builder): void

(* Copy string into builder *)
fun bput_loop {sn:nat}{fuel:nat} .<fuel>.
  (b: !$B.builder, s: string sn, slen: int sn, i: int, fuel: int fuel): void =
  if fuel <= 0 then ()
  else let
    val ii = $AR.checked_idx(i, slen)
    val c = char2int0(string_get_at(s, ii))
    val () = $B.put_byte(b, c)
  in bput_loop(b, s, slen, i + 1, fuel - 1) end

fn bput {sn:nat} (b: !$B.builder, s: string sn): void = let
  val slen_sz = string1_length(s)
  val slen = g1u2i(slen_sz)
in bput_loop(b, s, slen, 0, $AR.checked_nat(g0ofg1(slen) + 1)) end

implement produce_bridge(b) = let
  val () = bput(b, "// bats_bridge.mjs — Bridge between bats WASM and a DOM document\n")
  val () = bput(b, "// Parses the bats binary diff protocol and applies it to a standard DOM.\n")
  val () = bput(b, "// Works in any ES module environment (browser or Node.js).\n")
  val () = bput(b, "\n")
  val () = bput(b, "// Parse a little-endian i32 from a Uint8Array at offset\n")
  val () = bput(b, "function readI32(buf, off) {\n")
  val () = bput(b, "  return buf[off] | (buf[off+1] << 8) | (buf[off+2] << 16) | (buf[off+3] << 24);\n")
  val () = bput(b, "}\n")
  val () = bput(b, "\n")
  val () = bput(b, "/**\n")
  val () = bput(b, " * Load a bats WASM module and connect it to a DOM document.\n")
  val () = bput(b, " *\n")
  val () = bput(b, " * @param {BufferSource} wasmBytes — compiled WASM bytes\n")
  val () = bput(b, " * @param {Element} root — root element for bats to render into (node_id 0)\n")
  val () = bput(b, " * @returns {{ exports, nodes, done }} — WASM exports, node registry,\n")
  val () = bput(b, " *   and a promise that resolves when WASM calls bats_exit\n")
  val () = bput(b, " */\n")
  val () = bput(b, "export async function loadWASM(wasmBytes, root, opts) {\n")
  val () = bput(b, "  const extraImports = (opts && opts.extraImports) || {};\n")
  val () = bput(b, "  const document = root.ownerDocument;\n")
  val () = bput(b, "  let instance = null;\n")
  val () = bput(b, "  let resolveDone;\n")
  val () = bput(b, "  const done = new Promise(r => { resolveDone = r; });\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // Node registry: node_id -> DOM element\n")
  val () = bput(b, "  const nodes = new Map();\n")
  val () = bput(b, "  nodes.set(0, root);\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function readBytes(ptr, len) {\n")
  val () = bput(b, "    return new Uint8Array(instance.exports.memory.buffer, ptr, len).slice();\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function readString(ptr, len) {\n")
  val () = bput(b, "    return new TextDecoder().decode(readBytes(ptr, len));\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // JS-side data stash — WASM pulls data via bats_js_stash_read\n")
  val () = bput(b, "  const dataStash = new Map();\n")
  val () = bput(b, "  let nextStashId = 0;\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function stashData(data) {\n")
  val () = bput(b, "    const id = nextStashId++;\n")
  val () = bput(b, "    dataStash.set(id, data);\n")
  val () = bput(b, "    return id;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsStashRead(stashId, destPtr, len) {\n")
  val () = bput(b, "    const data = dataStash.get(stashId);\n")
  val () = bput(b, "    if (data) {\n")
  val () = bput(b, "      const copyLen = Math.min(len, data.length);\n")
  val () = bput(b, "      new Uint8Array(instance.exports.memory.buffer).set(\n")
  val () = bput(b, "        data.subarray(0, copyLen), destPtr);\n")
  val () = bput(b, "      dataStash.delete(stashId);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // Blob URL lifecycle tracking — revoked when element gets new image or is removed\n")
  val () = bput(b, "  const blobUrls = new Map();\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- DOM helpers ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // Remove all descendant entries from `nodes` and revoke their blob URLs.\n")
  val () = bput(b, "  // Called before clearing or removing an element that may have registered children.\n")
  val () = bput(b, "  function cleanDescendants(parentEl) {\n")
  val () = bput(b, "    for (const [id, node] of nodes) {\n")
  val () = bput(b, "      if (id !== 0 && node !== parentEl && parentEl.contains(node)) {\n")
  val () = bput(b, "        const oldUrl = blobUrls.get(id);\n")
  val () = bput(b, "        if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(id); }\n")
  val () = bput(b, "        nodes.delete(id);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- DOM flush ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsDomFlush(bufPtr, len) {\n")
  val () = bput(b, "    const mem = new Uint8Array(instance.exports.memory.buffer);\n")
  val () = bput(b, "    let pos = 0;\n")
  val () = bput(b, "\n")
  val () = bput(b, "    while (pos < len) {\n")
  val () = bput(b, "      const op = mem[bufPtr + pos];\n")
  val () = bput(b, "      const nodeId = readI32(mem, bufPtr + pos + 1);\n")
  val () = bput(b, "\n")
  val () = bput(b, "      switch (op) {\n")
  val () = bput(b, "        case 4: { // CREATE_ELEMENT\n")
  val () = bput(b, "          const parentId = readI32(mem, bufPtr + pos + 5);\n")
  val () = bput(b, "          const tagLen = mem[bufPtr + pos + 9];\n")
  val () = bput(b, "          const tag = new TextDecoder().decode(mem.slice(bufPtr + pos + 10, bufPtr + pos + 10 + tagLen));\n")
  val () = bput(b, "          const el = document.createElement(tag);\n")
  val () = bput(b, "          nodes.set(nodeId, el);\n")
  val () = bput(b, "          const parent = nodes.get(parentId);\n")
  val () = bput(b, "          if (parent) parent.appendChild(el);\n")
  val () = bput(b, "          pos += 10 + tagLen;\n")
  val () = bput(b, "          break;\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "        case 1: { // SET_TEXT\n")
  val () = bput(b, "          const textLen = mem[bufPtr + pos + 5] | (mem[bufPtr + pos + 6] << 8);\n")
  val () = bput(b, "          const text = new TextDecoder().decode(mem.slice(bufPtr + pos + 7, bufPtr + pos + 7 + textLen));\n")
  val () = bput(b, "          const el = nodes.get(nodeId);\n")
  val () = bput(b, "          if (el) el.textContent = text;\n")
  val () = bput(b, "          pos += 7 + textLen;\n")
  val () = bput(b, "          break;\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "        case 2: { // SET_ATTR\n")
  val () = bput(b, "          const nameLen = mem[bufPtr + pos + 5];\n")
  val () = bput(b, "          const name = new TextDecoder().decode(mem.slice(bufPtr + pos + 6, bufPtr + pos + 6 + nameLen));\n")
  val () = bput(b, "          const valOff = pos + 6 + nameLen;\n")
  val () = bput(b, "          const valLen = mem[bufPtr + valOff] | (mem[bufPtr + valOff + 1] << 8);\n")
  val () = bput(b, "          const value = new TextDecoder().decode(mem.slice(bufPtr + valOff + 2, bufPtr + valOff + 2 + valLen));\n")
  val () = bput(b, "          const el = nodes.get(nodeId);\n")
  val () = bput(b, "          if (el) el.setAttribute(name, value);\n")
  val () = bput(b, "          pos += 6 + nameLen + 2 + valLen;\n")
  val () = bput(b, "          break;\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "        case 3: { // REMOVE_CHILDREN\n")
  val () = bput(b, "          const el = nodes.get(nodeId);\n")
  val () = bput(b, "          if (el) {\n")
  val () = bput(b, "            cleanDescendants(el);\n")
  val () = bput(b, "            el.innerHTML = '';\n")
  val () = bput(b, "          }\n")
  val () = bput(b, "          pos += 5;\n")
  val () = bput(b, "          break;\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "        case 5: { // REMOVE_CHILD\n")
  val () = bput(b, "          const el = nodes.get(nodeId);\n")
  val () = bput(b, "          if (el) {\n")
  val () = bput(b, "            cleanDescendants(el);\n")
  val () = bput(b, "            el.remove();\n")
  val () = bput(b, "          }\n")
  val () = bput(b, "          const oldUrl = blobUrls.get(nodeId);\n")
  val () = bput(b, "          if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(nodeId); }\n")
  val () = bput(b, "          nodes.delete(nodeId);\n")
  val () = bput(b, "          pos += 5;\n")
  val () = bput(b, "          break;\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "        default:\n")
  val () = bput(b, "          throw new Error(`Unknown bats DOM op: ${op} at offset ${pos}`);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Image src (direct bridge call, not diff buffer) ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsSetImageSrc(nodeId, dataPtr, dataLen, mimePtr, mimeLen) {\n")
  val () = bput(b, "    const mime = readString(mimePtr, mimeLen);\n")
  val () = bput(b, "    const bytes = readBytes(dataPtr, dataLen);\n")
  val () = bput(b, "    const oldUrl = blobUrls.get(nodeId);\n")
  val () = bput(b, "    if (oldUrl) URL.revokeObjectURL(oldUrl);\n")
  val () = bput(b, "    const blob = new Blob([bytes], { type: mime });\n")
  val () = bput(b, "    const url = URL.createObjectURL(blob);\n")
  val () = bput(b, "    const el = nodes.get(nodeId);\n")
  val () = bput(b, "    if (el) el.src = url;\n")
  val () = bput(b, "    blobUrls.set(nodeId, url);\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Timer ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsSetTimer(delayMs, resolverId) {\n")
  val () = bput(b, "    setTimeout(() => {\n")
  val () = bput(b, "      instance.exports.bats_timer_fire(resolverId);\n")
  val () = bput(b, "    }, delayMs);\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- IndexedDB ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  let dbPromise = null;\n")
  val () = bput(b, "  function openDB() {\n")
  val () = bput(b, "    if (!dbPromise) {\n")
  val () = bput(b, "      dbPromise = new Promise((resolve, reject) => {\n")
  val () = bput(b, "        const req = indexedDB.open('bats', 1);\n")
  val () = bput(b, "        req.onupgradeneeded = () => {\n")
  val () = bput(b, "          req.result.createObjectStore('kv');\n")
  val () = bput(b, "        };\n")
  val () = bput(b, "        req.onsuccess = () => resolve(req.result);\n")
  val () = bput(b, "        req.onerror = () => reject(req.error);\n")
  val () = bput(b, "      });\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    return dbPromise;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsIdbPut(keyPtr, keyLen, valPtr, valLen, resolverId) {\n")
  val () = bput(b, "    const key = readString(keyPtr, keyLen);\n")
  val () = bput(b, "    const val = readBytes(valPtr, valLen);\n")
  val () = bput(b, "    openDB().then(db => {\n")
  val () = bput(b, "      const tx = db.transaction('kv', 'readwrite');\n")
  val () = bput(b, "      tx.objectStore('kv').put(val, key);\n")
  val () = bput(b, "      tx.oncomplete = () => {\n")
  val () = bput(b, "        instance.exports.bats_idb_fire(resolverId, 0);\n")
  val () = bput(b, "      };\n")
  val () = bput(b, "      tx.onerror = () => {\n")
  val () = bput(b, "        instance.exports.bats_idb_fire(resolverId, -1);\n")
  val () = bput(b, "      };\n")
  val () = bput(b, "    });\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsIdbGet(keyPtr, keyLen, resolverId) {\n")
  val () = bput(b, "    const key = readString(keyPtr, keyLen);\n")
  val () = bput(b, "    openDB().then(db => {\n")
  val () = bput(b, "      const tx = db.transaction('kv', 'readonly');\n")
  val () = bput(b, "      const req = tx.objectStore('kv').get(key);\n")
  val () = bput(b, "      req.onsuccess = () => {\n")
  val () = bput(b, "        const result = req.result;\n")
  val () = bput(b, "        if (result === undefined) {\n")
  val () = bput(b, "          instance.exports.bats_idb_fire_get(resolverId, 0);\n")
  val () = bput(b, "        } else {\n")
  val () = bput(b, "          const data = new Uint8Array(result);\n")
  val () = bput(b, "          const stashId = stashData(data);\n")
  val () = bput(b, "          instance.exports.bats_bridge_stash_set_int(1, stashId);\n")
  val () = bput(b, "          instance.exports.bats_idb_fire_get(resolverId, data.length);\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "      };\n")
  val () = bput(b, "      req.onerror = () => {\n")
  val () = bput(b, "        instance.exports.bats_idb_fire_get(resolverId, 0);\n")
  val () = bput(b, "      };\n")
  val () = bput(b, "    });\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsIdbDelete(keyPtr, keyLen, resolverId) {\n")
  val () = bput(b, "    const key = readString(keyPtr, keyLen);\n")
  val () = bput(b, "    openDB().then(db => {\n")
  val () = bput(b, "      const tx = db.transaction('kv', 'readwrite');\n")
  val () = bput(b, "      tx.objectStore('kv').delete(key);\n")
  val () = bput(b, "      tx.oncomplete = () => {\n")
  val () = bput(b, "        instance.exports.bats_idb_fire(resolverId, 0);\n")
  val () = bput(b, "      };\n")
  val () = bput(b, "      tx.onerror = () => {\n")
  val () = bput(b, "        instance.exports.bats_idb_fire(resolverId, -1);\n")
  val () = bput(b, "      };\n")
  val () = bput(b, "    });\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Window ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsFocusWindow() {\n")
  val () = bput(b, "    try { root.ownerDocument.defaultView.focus(); } catch(e) {}\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsGetVisibilityState() {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      return document.visibilityState === 'hidden' ? 1 : 0;\n")
  val () = bput(b, "    } catch(e) { return 0; }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsLog(level, msgPtr, msgLen) {\n")
  val () = bput(b, "    const msg = readString(msgPtr, msgLen);\n")
  val () = bput(b, "    const labels = ['debug', 'info', 'warn', 'error'];\n")
  val () = bput(b, "    const label = labels[level] || 'log';\n")
  val () = bput(b, "    console.log(`[bats:${label}] ${msg}`);\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Navigation ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function writeStringToWasm(str, outPtr, maxLen) {\n")
  val () = bput(b, "    const encoded = new TextEncoder().encode(str);\n")
  val () = bput(b, "    const len = Math.min(encoded.length, maxLen);\n")
  val () = bput(b, "    new Uint8Array(instance.exports.memory.buffer).set(encoded.subarray(0, len), outPtr);\n")
  val () = bput(b, "    return len;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsGetUrl(outPtr, maxLen) {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView;\n")
  val () = bput(b, "      return writeStringToWasm(win.location.href, outPtr, maxLen);\n")
  val () = bput(b, "    } catch(e) { return 0; }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsGetUrlHash(outPtr, maxLen) {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView;\n")
  val () = bput(b, "      return writeStringToWasm(win.location.hash, outPtr, maxLen);\n")
  val () = bput(b, "    } catch(e) { return 0; }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsSetUrlHash(hashPtr, hashLen) {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView;\n")
  val () = bput(b, "      win.location.hash = readString(hashPtr, hashLen);\n")
  val () = bput(b, "    } catch(e) {}\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsReplaceState(urlPtr, urlLen) {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView;\n")
  val () = bput(b, "      win.history.replaceState(null, '', readString(urlPtr, urlLen));\n")
  val () = bput(b, "    } catch(e) {}\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsPushState(urlPtr, urlLen) {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView;\n")
  val () = bput(b, "      win.history.pushState(null, '', readString(urlPtr, urlLen));\n")
  val () = bput(b, "    } catch(e) {}\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- DOM read ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsMeasureNode(nodeId) {\n")
  val () = bput(b, "    const el = nodes.get(nodeId);\n")
  val () = bput(b, "    if (el && typeof el.getBoundingClientRect === 'function') {\n")
  val () = bput(b, "      const rect = el.getBoundingClientRect();\n")
  val () = bput(b, "      instance.exports.bats_measure_set(0, Math.round(rect.x));\n")
  val () = bput(b, "      instance.exports.bats_measure_set(1, Math.round(rect.y));\n")
  val () = bput(b, "      instance.exports.bats_measure_set(2, Math.round(rect.width));\n")
  val () = bput(b, "      instance.exports.bats_measure_set(3, Math.round(rect.height));\n")
  val () = bput(b, "      instance.exports.bats_measure_set(4, el.scrollWidth || 0);\n")
  val () = bput(b, "      instance.exports.bats_measure_set(5, el.scrollHeight || 0);\n")
  val () = bput(b, "      return 1;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    for (let i = 0; i < 6; i++) {\n")
  val () = bput(b, "      instance.exports.bats_measure_set(i, 0);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    return 0;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsQuerySelector(selectorPtr, selectorLen) {\n")
  val () = bput(b, "    const selector = readString(selectorPtr, selectorLen);\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const el = document.querySelector(selector);\n")
  val () = bput(b, "      if (!el) return -1;\n")
  val () = bput(b, "      for (const [id, node] of nodes) {\n")
  val () = bput(b, "        if (node === el) return id;\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "      return -1;\n")
  val () = bput(b, "    } catch(e) { return -1; }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Event listener ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  const listenerMap = new Map();\n")
  val () = bput(b, "  let currentEvent = null;\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // Encode event payload as binary (little-endian).\n")
  val () = bput(b, "  // Returns Uint8Array or null for no payload.\n")
  val () = bput(b, "  function encodeEventPayload(event, eventType) {\n")
  val () = bput(b, "    if (eventType === 'click' || eventType === 'pointerdown' ||\n")
  val () = bput(b, "        eventType === 'pointerup' || eventType === 'pointermove') {\n")
  val () = bput(b, "      // [f64:clientX] [f64:clientY] [i32:target_node_id]\n")
  val () = bput(b, "      const buf = new ArrayBuffer(20);\n")
  val () = bput(b, "      const dv = new DataView(buf);\n")
  val () = bput(b, "      dv.setFloat64(0, event.clientX || 0, true);\n")
  val () = bput(b, "      dv.setFloat64(8, event.clientY || 0, true);\n")
  val () = bput(b, "      let targetId = -1;\n")
  val () = bput(b, "      if (event.target) {\n")
  val () = bput(b, "        for (const [id, node] of nodes) {\n")
  val () = bput(b, "          if (node === event.target) { targetId = id; break; }\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "      dv.setInt32(16, targetId, true);\n")
  val () = bput(b, "      return new Uint8Array(buf);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    if (eventType === 'keydown' || eventType === 'keyup') {\n")
  val () = bput(b, "      // [u8:keyLen] [bytes:key] [u8:flags]\n")
  val () = bput(b, "      const key = event.key || '';\n")
  val () = bput(b, "      const keyBytes = new TextEncoder().encode(key);\n")
  val () = bput(b, "      const buf = new Uint8Array(1 + keyBytes.length + 1);\n")
  val () = bput(b, "      buf[0] = keyBytes.length;\n")
  val () = bput(b, "      buf.set(keyBytes, 1);\n")
  val () = bput(b, "      const flags = (event.shiftKey ? 1 : 0) | (event.ctrlKey ? 2 : 0) |\n")
  val () = bput(b, "                    (event.altKey ? 4 : 0) | (event.metaKey ? 8 : 0);\n")
  val () = bput(b, "      buf[1 + keyBytes.length] = flags;\n")
  val () = bput(b, "      return buf;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    if (eventType === 'input') {\n")
  val () = bput(b, "      // [u16le:value_len] [bytes:value]\n")
  val () = bput(b, "      const value = (event.target && event.target.value) || '';\n")
  val () = bput(b, "      const valBytes = new TextEncoder().encode(value);\n")
  val () = bput(b, "      const buf = new Uint8Array(2 + valBytes.length);\n")
  val () = bput(b, "      buf[0] = valBytes.length & 0xFF;\n")
  val () = bput(b, "      buf[1] = (valBytes.length >> 8) & 0xFF;\n")
  val () = bput(b, "      buf.set(valBytes, 2);\n")
  val () = bput(b, "      return buf;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    if (eventType === 'scroll') {\n")
  val () = bput(b, "      // [f64:scrollTop] [f64:scrollLeft]\n")
  val () = bput(b, "      const buf = new ArrayBuffer(16);\n")
  val () = bput(b, "      const dv = new DataView(buf);\n")
  val () = bput(b, "      const target = event.target || {};\n")
  val () = bput(b, "      dv.setFloat64(0, target.scrollTop || 0, true);\n")
  val () = bput(b, "      dv.setFloat64(8, target.scrollLeft || 0, true);\n")
  val () = bput(b, "      return new Uint8Array(buf);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    if (eventType === 'resize') {\n")
  val () = bput(b, "      // [f64:width] [f64:height]\n")
  val () = bput(b, "      const buf = new ArrayBuffer(16);\n")
  val () = bput(b, "      const dv = new DataView(buf);\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView || {};\n")
  val () = bput(b, "      dv.setFloat64(0, win.innerWidth || 0, true);\n")
  val () = bput(b, "      dv.setFloat64(8, win.innerHeight || 0, true);\n")
  val () = bput(b, "      return new Uint8Array(buf);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    if (eventType === 'touchstart' || eventType === 'touchend' || eventType === 'touchmove') {\n")
  val () = bput(b, "      // [f64:clientX] [f64:clientY] [i32:identifier]\n")
  val () = bput(b, "      const touch = (event.touches && event.touches[0]) ||\n")
  val () = bput(b, "                    (event.changedTouches && event.changedTouches[0]);\n")
  val () = bput(b, "      if (touch) {\n")
  val () = bput(b, "        const buf = new ArrayBuffer(20);\n")
  val () = bput(b, "        const dv = new DataView(buf);\n")
  val () = bput(b, "        dv.setFloat64(0, touch.clientX || 0, true);\n")
  val () = bput(b, "        dv.setFloat64(8, touch.clientY || 0, true);\n")
  val () = bput(b, "        dv.setInt32(16, touch.identifier || 0, true);\n")
  val () = bput(b, "        return new Uint8Array(buf);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "      return null;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    if (eventType === 'visibilitychange') {\n")
  val () = bput(b, "      // [u8:hidden]\n")
  val () = bput(b, "      return new Uint8Array([document.visibilityState === 'hidden' ? 1 : 0]);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    return null;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsAddEventListener(nodeId, eventTypePtr, typeLen, listenerId) {\n")
  val () = bput(b, "    const node = nodes.get(nodeId);\n")
  val () = bput(b, "    if (!node) return;\n")
  val () = bput(b, "    const eventType = readString(eventTypePtr, typeLen);\n")
  val () = bput(b, "    const handler = (event) => {\n")
  val () = bput(b, "      currentEvent = event;\n")
  val () = bput(b, "      const payload = encodeEventPayload(event, eventType);\n")
  val () = bput(b, "      if (payload) {\n")
  val () = bput(b, "        const stashId = stashData(payload);\n")
  val () = bput(b, "        instance.exports.bats_bridge_stash_set_int(1, stashId);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "      instance.exports.bats_on_event(listenerId, payload ? payload.length : 0);\n")
  val () = bput(b, "      currentEvent = null;\n")
  val () = bput(b, "    };\n")
  val () = bput(b, "    listenerMap.set(listenerId, { node, eventType, handler });\n")
  val () = bput(b, "    node.addEventListener(eventType, handler);\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsRemoveEventListener(listenerId) {\n")
  val () = bput(b, "    const entry = listenerMap.get(listenerId);\n")
  val () = bput(b, "    if (entry) {\n")
  val () = bput(b, "      entry.node.removeEventListener(entry.eventType, entry.handler);\n")
  val () = bput(b, "      listenerMap.delete(listenerId);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsPreventDefault() {\n")
  val () = bput(b, "    if (currentEvent) currentEvent.preventDefault();\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Fetch ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsFetch(urlPtr, urlLen, resolverId) {\n")
  val () = bput(b, "    const url = readString(urlPtr, urlLen);\n")
  val () = bput(b, "    fetch(url).then(async (response) => {\n")
  val () = bput(b, "      const body = new Uint8Array(await response.arrayBuffer());\n")
  val () = bput(b, "      if (body.length > 0) {\n")
  val () = bput(b, "        const stashId = stashData(body);\n")
  val () = bput(b, "        instance.exports.bats_bridge_stash_set_int(1, stashId);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "      instance.exports.bats_on_fetch_complete(resolverId, response.status, body.length);\n")
  val () = bput(b, "    }).catch(() => {\n")
  val () = bput(b, "      instance.exports.bats_on_fetch_complete(resolverId, 0, 0);\n")
  val () = bput(b, "    });\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Clipboard ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsClipboardWriteText(textPtr, textLen, resolverId) {\n")
  val () = bput(b, "    const text = readString(textPtr, textLen);\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView;\n")
  val () = bput(b, "      if (win && win.navigator && win.navigator.clipboard) {\n")
  val () = bput(b, "        win.navigator.clipboard.writeText(text).then(\n")
  val () = bput(b, "          () => { instance.exports.bats_on_clipboard_complete(resolverId, 1); },\n")
  val () = bput(b, "          () => { instance.exports.bats_on_clipboard_complete(resolverId, 0); }\n")
  val () = bput(b, "        );\n")
  val () = bput(b, "      } else {\n")
  val () = bput(b, "        instance.exports.bats_on_clipboard_complete(resolverId, 0);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "    } catch(e) {\n")
  val () = bput(b, "      instance.exports.bats_on_clipboard_complete(resolverId, 0);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- File ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  const fileCache = new Map();\n")
  val () = bput(b, "  let nextFileHandle = 1;\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsFileOpen(inputNodeId, resolverId) {\n")
  val () = bput(b, "    const el = nodes.get(inputNodeId);\n")
  val () = bput(b, "    if (!el || !el.files || !el.files[0]) {\n")
  val () = bput(b, "      instance.exports.bats_bridge_stash_set_int(2, 0);\n")
  val () = bput(b, "      instance.exports.bats_on_file_open(resolverId, 0, 0);\n")
  val () = bput(b, "      return;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    const file = el.files[0];\n")
  val () = bput(b, "    const reader = new FileReader();\n")
  val () = bput(b, "    reader.onload = () => {\n")
  val () = bput(b, "      const handle = nextFileHandle++;\n")
  val () = bput(b, "      const data = new Uint8Array(reader.result);\n")
  val () = bput(b, "      fileCache.set(handle, data);\n")
  val () = bput(b, "      const nameBytes = new TextEncoder().encode(file.name);\n")
  val () = bput(b, "      const nameStashId = stashData(nameBytes);\n")
  val () = bput(b, "      instance.exports.bats_bridge_stash_set_int(1, nameStashId);\n")
  val () = bput(b, "      instance.exports.bats_bridge_stash_set_int(2, nameBytes.length);\n")
  val () = bput(b, "      instance.exports.bats_on_file_open(resolverId, handle, data.length);\n")
  val () = bput(b, "    };\n")
  val () = bput(b, "    reader.onerror = () => {\n")
  val () = bput(b, "      instance.exports.bats_bridge_stash_set_int(2, 0);\n")
  val () = bput(b, "      instance.exports.bats_on_file_open(resolverId, 0, 0);\n")
  val () = bput(b, "    };\n")
  val () = bput(b, "    reader.readAsArrayBuffer(file);\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsFileRead(handle, fileOffset, len, outPtr) {\n")
  val () = bput(b, "    const data = fileCache.get(handle);\n")
  val () = bput(b, "    if (!data) return 0;\n")
  val () = bput(b, "    const available = Math.max(0, data.length - fileOffset);\n")
  val () = bput(b, "    const copyLen = Math.min(len, available);\n")
  val () = bput(b, "    if (copyLen > 0) {\n")
  val () = bput(b, "      new Uint8Array(instance.exports.memory.buffer).set(\n")
  val () = bput(b, "        data.subarray(fileOffset, fileOffset + copyLen), outPtr);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    return copyLen;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsFileClose(handle) {\n")
  val () = bput(b, "    fileCache.delete(handle);\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Decompress ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  const blobCache = new Map();\n")
  val () = bput(b, "  let nextBlobHandle = 1;\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsDecompress(dataPtr, dataLen, method, resolverId) {\n")
  val () = bput(b, "    const compressed = readBytes(dataPtr, dataLen);\n")
  val () = bput(b, "    const formats = ['gzip', 'deflate', 'deflate-raw'];\n")
  val () = bput(b, "    const format = formats[method];\n")
  val () = bput(b, "    if (!format || typeof DecompressionStream === 'undefined') {\n")
  val () = bput(b, "      instance.exports.bats_on_decompress_complete(resolverId, 0, 0);\n")
  val () = bput(b, "      return;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    const ds = new DecompressionStream(format);\n")
  val () = bput(b, "    const writer = ds.writable.getWriter();\n")
  val () = bput(b, "    writer.write(compressed);\n")
  val () = bput(b, "    writer.close();\n")
  val () = bput(b, "    const reader = ds.readable.getReader();\n")
  val () = bput(b, "    const chunks = [];\n")
  val () = bput(b, "    (function pump() {\n")
  val () = bput(b, "      reader.read().then(({ done, value }) => {\n")
  val () = bput(b, "        if (value) chunks.push(value);\n")
  val () = bput(b, "        if (done) {\n")
  val () = bput(b, "          let totalLen = 0;\n")
  val () = bput(b, "          for (const c of chunks) totalLen += c.length;\n")
  val () = bput(b, "          const result = new Uint8Array(totalLen);\n")
  val () = bput(b, "          let off = 0;\n")
  val () = bput(b, "          for (const c of chunks) { result.set(c, off); off += c.length; }\n")
  val () = bput(b, "          const handle = nextBlobHandle++;\n")
  val () = bput(b, "          blobCache.set(handle, result);\n")
  val () = bput(b, "          instance.exports.bats_on_decompress_complete(resolverId, handle, result.length);\n")
  val () = bput(b, "        } else {\n")
  val () = bput(b, "          pump();\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "      }).catch(() => {\n")
  val () = bput(b, "        instance.exports.bats_on_decompress_complete(resolverId, 0, 0);\n")
  val () = bput(b, "      });\n")
  val () = bput(b, "    })();\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsBlobRead(handle, blobOffset, len, outPtr) {\n")
  val () = bput(b, "    const data = blobCache.get(handle);\n")
  val () = bput(b, "    if (!data) return 0;\n")
  val () = bput(b, "    const available = Math.max(0, data.length - blobOffset);\n")
  val () = bput(b, "    const copyLen = Math.min(len, available);\n")
  val () = bput(b, "    if (copyLen > 0) {\n")
  val () = bput(b, "      new Uint8Array(instance.exports.memory.buffer).set(\n")
  val () = bput(b, "        data.subarray(blobOffset, blobOffset + copyLen), outPtr);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    return copyLen;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsBlobFree(handle) {\n")
  val () = bput(b, "    blobCache.delete(handle);\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- Notification/Push ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsNotificationRequestPermission(resolverId) {\n")
  val () = bput(b, "    if (typeof Notification === 'undefined') {\n")
  val () = bput(b, "      instance.exports.bats_on_permission_result(resolverId, 0);\n")
  val () = bput(b, "      return;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    Notification.requestPermission().then((perm) => {\n")
  val () = bput(b, "      instance.exports.bats_on_permission_result(resolverId, perm === 'granted' ? 1 : 0);\n")
  val () = bput(b, "    }).catch(() => {\n")
  val () = bput(b, "      instance.exports.bats_on_permission_result(resolverId, 0);\n")
  val () = bput(b, "    });\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsNotificationShow(titlePtr, titleLen) {\n")
  val () = bput(b, "    if (typeof Notification === 'undefined') return;\n")
  val () = bput(b, "    const title = readString(titlePtr, titleLen);\n")
  val () = bput(b, "    try { new Notification(title); } catch(e) {}\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsPushSubscribe(vapidPtr, vapidLen, resolverId) {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const vapidBytes = readBytes(vapidPtr, vapidLen);\n")
  val () = bput(b, "      navigator.serviceWorker.ready.then((reg) => {\n")
  val () = bput(b, "        return reg.pushManager.subscribe({\n")
  val () = bput(b, "          userVisibleOnly: true,\n")
  val () = bput(b, "          applicationServerKey: vapidBytes,\n")
  val () = bput(b, "        });\n")
  val () = bput(b, "      }).then((sub) => {\n")
  val () = bput(b, "        const json = JSON.stringify(sub.toJSON());\n")
  val () = bput(b, "        const jsonBytes = new TextEncoder().encode(json);\n")
  val () = bput(b, "        const stashId = stashData(jsonBytes);\n")
  val () = bput(b, "        instance.exports.bats_bridge_stash_set_int(1, stashId);\n")
  val () = bput(b, "        instance.exports.bats_on_push_subscribe(resolverId, jsonBytes.length);\n")
  val () = bput(b, "      }).catch(() => {\n")
  val () = bput(b, "        instance.exports.bats_on_push_subscribe(resolverId, 0);\n")
  val () = bput(b, "      });\n")
  val () = bput(b, "    } catch(e) {\n")
  val () = bput(b, "      instance.exports.bats_on_push_subscribe(resolverId, 0);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsPushGetSubscription(resolverId) {\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      navigator.serviceWorker.ready.then((reg) => {\n")
  val () = bput(b, "        return reg.pushManager.getSubscription();\n")
  val () = bput(b, "      }).then((sub) => {\n")
  val () = bput(b, "        if (!sub) {\n")
  val () = bput(b, "          instance.exports.bats_on_push_subscribe(resolverId, 0);\n")
  val () = bput(b, "          return;\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "        const json = JSON.stringify(sub.toJSON());\n")
  val () = bput(b, "        const jsonBytes = new TextEncoder().encode(json);\n")
  val () = bput(b, "        const stashId = stashData(jsonBytes);\n")
  val () = bput(b, "        instance.exports.bats_bridge_stash_set_int(1, stashId);\n")
  val () = bput(b, "        instance.exports.bats_on_push_subscribe(resolverId, jsonBytes.length);\n")
  val () = bput(b, "      }).catch(() => {\n")
  val () = bput(b, "        instance.exports.bats_on_push_subscribe(resolverId, 0);\n")
  val () = bput(b, "      });\n")
  val () = bput(b, "    } catch(e) {\n")
  val () = bput(b, "      instance.exports.bats_on_push_subscribe(resolverId, 0);\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // --- HTML parsing ---\n")
  val () = bput(b, "\n")
  val () = bput(b, "  // Tags filtered out during parsing (security/sanitization)\n")
  val () = bput(b, "  const FILTERED_TAGS = new Set([\n")
  val () = bput(b, "    'script', 'iframe', 'object', 'embed', 'form', 'input', 'link', 'meta'\n")
  val () = bput(b, "  ]);\n")
  val () = bput(b, "\n")
  val () = bput(b, "  function batsJsParseHtml(htmlPtr, htmlLen) {\n")
  val () = bput(b, "    const html = readString(htmlPtr, htmlLen);\n")
  val () = bput(b, "    let doc;\n")
  val () = bput(b, "    try {\n")
  val () = bput(b, "      const win = root.ownerDocument.defaultView;\n")
  val () = bput(b, "      if (typeof win.DOMParser !== 'undefined') {\n")
  val () = bput(b, "        doc = new win.DOMParser().parseFromString(html, 'text/html');\n")
  val () = bput(b, "      } else {\n")
  val () = bput(b, "        return 0;\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "    } catch(e) { return 0; }\n")
  val () = bput(b, "\n")
  val () = bput(b, "    // Serialize DOM tree to binary SAX format\n")
  val () = bput(b, "    const chunks = [];\n")
  val () = bput(b, "    let totalLen = 0;\n")
  val () = bput(b, "\n")
  val () = bput(b, "    function pushByte(b) { chunks.push(new Uint8Array([b])); totalLen += 1; }\n")
  val () = bput(b, "    function pushU16LE(v) { chunks.push(new Uint8Array([v & 0xFF, (v >> 8) & 0xFF])); totalLen += 2; }\n")
  val () = bput(b, "    function pushBytes(arr) { chunks.push(arr); totalLen += arr.length; }\n")
  val () = bput(b, "\n")
  val () = bput(b, "    function serializeNode(node) {\n")
  val () = bput(b, "      if (node.nodeType === 1) { // ELEMENT_NODE\n")
  val () = bput(b, "        const tag = node.tagName.toLowerCase();\n")
  val () = bput(b, "        if (FILTERED_TAGS.has(tag)) return;\n")
  val () = bput(b, "        const tagBytes = new TextEncoder().encode(tag);\n")
  val () = bput(b, "        if (tagBytes.length > 255) return;\n")
  val () = bput(b, "\n")
  val () = bput(b, "        // Collect safe attributes\n")
  val () = bput(b, "        const attrs = [];\n")
  val () = bput(b, "        for (let i = 0; i < node.attributes.length; i++) {\n")
  val () = bput(b, "          const attr = node.attributes[i];\n")
  val () = bput(b, "          if (/^on/i.test(attr.name)) continue;    // skip event handlers\n")
  val () = bput(b, "          if (attr.name === 'style') continue;       // skip style\n")
  val () = bput(b, "          if (!/^[a-zA-Z0-9-]+$/.test(attr.name)) continue; // skip non-safe names\n")
  val () = bput(b, "          const nameBytes = new TextEncoder().encode(attr.name);\n")
  val () = bput(b, "          const valBytes = new TextEncoder().encode(attr.value);\n")
  val () = bput(b, "          if (nameBytes.length > 255 || valBytes.length > 65535) continue;\n")
  val () = bput(b, "          attrs.push({ nameBytes, valBytes });\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "\n")
  val () = bput(b, "        // ELEMENT_OPEN: [0x01] [u8:tag_len] [bytes:tag] [u8:attr_count]\n")
  val () = bput(b, "        pushByte(0x01);\n")
  val () = bput(b, "        pushByte(tagBytes.length);\n")
  val () = bput(b, "        pushBytes(tagBytes);\n")
  val () = bput(b, "        pushByte(attrs.length);\n")
  val () = bput(b, "\n")
  val () = bput(b, "        // per attr: [u8:name_len] [bytes:name] [u16le:value_len] [bytes:value]\n")
  val () = bput(b, "        for (const a of attrs) {\n")
  val () = bput(b, "          pushByte(a.nameBytes.length);\n")
  val () = bput(b, "          pushBytes(a.nameBytes);\n")
  val () = bput(b, "          pushU16LE(a.valBytes.length);\n")
  val () = bput(b, "          pushBytes(a.valBytes);\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "\n")
  val () = bput(b, "        // Recurse children\n")
  val () = bput(b, "        for (let i = 0; i < node.childNodes.length; i++) {\n")
  val () = bput(b, "          serializeNode(node.childNodes[i]);\n")
  val () = bput(b, "        }\n")
  val () = bput(b, "\n")
  val () = bput(b, "        // ELEMENT_CLOSE: [0x02]\n")
  val () = bput(b, "        pushByte(0x02);\n")
  val () = bput(b, "      } else if (node.nodeType === 3) { // TEXT_NODE\n")
  val () = bput(b, "        const text = node.textContent || '';\n")
  val () = bput(b, "        if (text.length === 0) return;\n")
  val () = bput(b, "        const textBytes = new TextEncoder().encode(text);\n")
  val () = bput(b, "        if (textBytes.length > 65535) return;\n")
  val () = bput(b, "        // TEXT: [0x03] [u16le:text_len] [bytes:text]\n")
  val () = bput(b, "        pushByte(0x03);\n")
  val () = bput(b, "        pushU16LE(textBytes.length);\n")
  val () = bput(b, "        pushBytes(textBytes);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "\n")
  val () = bput(b, "    // Serialize body children (skip <html>, <head>, <body> wrappers)\n")
  val () = bput(b, "    const body = doc.body;\n")
  val () = bput(b, "    if (body) {\n")
  val () = bput(b, "      for (let i = 0; i < body.childNodes.length; i++) {\n")
  val () = bput(b, "        serializeNode(body.childNodes[i]);\n")
  val () = bput(b, "      }\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "\n")
  val () = bput(b, "    if (totalLen === 0) return 0;\n")
  val () = bput(b, "\n")
  val () = bput(b, "    // Combine chunks and stash for WASM to pull\n")
  val () = bput(b, "    const combined = new Uint8Array(totalLen);\n")
  val () = bput(b, "    let off = 0;\n")
  val () = bput(b, "    for (const chunk of chunks) {\n")
  val () = bput(b, "      combined.set(chunk, off);\n")
  val () = bput(b, "      off += chunk.length;\n")
  val () = bput(b, "    }\n")
  val () = bput(b, "    const stashId = stashData(combined);\n")
  val () = bput(b, "    instance.exports.bats_bridge_stash_set_int(1, stashId);\n")
  val () = bput(b, "    return totalLen;\n")
  val () = bput(b, "  }\n")
  val () = bput(b, "\n")
  val () = bput(b, "  const imports = {\n")
  val () = bput(b, "    env: {\n")
  val () = bput(b, "      ...extraImports,\n")
  val () = bput(b, "      bats_dom_flush: batsDomFlush,\n")
  val () = bput(b, "      bats_js_set_image_src: batsJsSetImageSrc,\n")
  val () = bput(b, "      bats_set_timer: batsSetTimer,\n")
  val () = bput(b, "      bats_exit: () => { resolveDone(); },\n")
  val () = bput(b, "      // IDB\n")
  val () = bput(b, "      bats_idb_js_put: batsIdbPut,\n")
  val () = bput(b, "      bats_idb_js_get: batsIdbGet,\n")
  val () = bput(b, "      bats_idb_js_delete: batsIdbDelete,\n")
  val () = bput(b, "      // Window\n")
  val () = bput(b, "      bats_js_focus_window: batsJsFocusWindow,\n")
  val () = bput(b, "      bats_js_get_visibility_state: batsJsGetVisibilityState,\n")
  val () = bput(b, "      bats_js_log: batsJsLog,\n")
  val () = bput(b, "      // Navigation\n")
  val () = bput(b, "      bats_js_get_url: batsJsGetUrl,\n")
  val () = bput(b, "      bats_js_get_url_hash: batsJsGetUrlHash,\n")
  val () = bput(b, "      bats_js_set_url_hash: batsJsSetUrlHash,\n")
  val () = bput(b, "      bats_js_replace_state: batsJsReplaceState,\n")
  val () = bput(b, "      bats_js_push_state: batsJsPushState,\n")
  val () = bput(b, "      // DOM read\n")
  val () = bput(b, "      bats_js_measure_node: batsJsMeasureNode,\n")
  val () = bput(b, "      bats_js_query_selector: batsJsQuerySelector,\n")
  val () = bput(b, "      // Event listener\n")
  val () = bput(b, "      bats_js_add_event_listener: batsJsAddEventListener,\n")
  val () = bput(b, "      bats_js_remove_event_listener: batsJsRemoveEventListener,\n")
  val () = bput(b, "      bats_js_prevent_default: batsJsPreventDefault,\n")
  val () = bput(b, "      // Fetch\n")
  val () = bput(b, "      bats_js_fetch: batsJsFetch,\n")
  val () = bput(b, "      // Clipboard\n")
  val () = bput(b, "      bats_js_clipboard_write_text: batsJsClipboardWriteText,\n")
  val () = bput(b, "      // File\n")
  val () = bput(b, "      bats_js_file_open: batsJsFileOpen,\n")
  val () = bput(b, "      bats_js_file_read: batsJsFileRead,\n")
  val () = bput(b, "      bats_js_file_close: batsJsFileClose,\n")
  val () = bput(b, "      // Decompress\n")
  val () = bput(b, "      bats_js_decompress: batsJsDecompress,\n")
  val () = bput(b, "      bats_js_blob_read: batsJsBlobRead,\n")
  val () = bput(b, "      bats_js_blob_free: batsJsBlobFree,\n")
  val () = bput(b, "      // Notification/Push\n")
  val () = bput(b, "      bats_js_notification_request_permission: batsJsNotificationRequestPermission,\n")
  val () = bput(b, "      bats_js_notification_show: batsJsNotificationShow,\n")
  val () = bput(b, "      bats_js_push_subscribe: batsJsPushSubscribe,\n")
  val () = bput(b, "      bats_js_push_get_subscription: batsJsPushGetSubscription,\n")
  val () = bput(b, "      // HTML parsing\n")
  val () = bput(b, "      bats_js_parse_html: batsJsParseHtml,\n")
  val () = bput(b, "      // Data stash\n")
  val () = bput(b, "      bats_js_stash_read: batsJsStashRead,\n")
  val () = bput(b, "    },\n")
  val () = bput(b, "  };\n")
  val () = bput(b, "\n")
  val () = bput(b, "  const result = await WebAssembly.instantiate(wasmBytes, imports);\n")
  val () = bput(b, "  instance = result.instance;\n")
  val () = bput(b, "  instance.exports.bats_node_init(0);\n")
  val () = bput(b, "\n")
  val () = bput(b, "  return { exports: instance.exports, nodes, done };\n")
  val () = bput(b, "}\n")
in end
#use result as R

staload "./lib.sats"

(* ============================================================
   Internal -- extern WASM imports (all mac# declarations)
   ============================================================ *)

#target wasm begin

(* --- Timer --- *)
extern fun _bats_set_timer
  (delay_ms: int, resolver_id: int): void = "mac#bats_set_timer"
extern fun _bats_exit
  (): void = "mac#bats_exit"

(* --- DOM --- *)
extern fun _bats_dom_flush
  (buf: ptr, len: int): void = "mac#bats_dom_flush"
extern fun _bats_js_set_image_src
  (node_id: int, data: ptr, data_len: int, mime: ptr, mime_len: int)
  : void = "mac#bats_js_set_image_src"

(* --- DOM read --- *)
extern fun _bats_js_measure_node
  (node_id: int): int = "mac#bats_js_measure_node"
extern fun _bats_js_query_selector
  (selector: ptr, selector_len: int): int = "mac#bats_js_query_selector"

(* --- Event --- *)
extern fun _bats_js_add_event_listener
  (node_id: int, event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#bats_js_add_event_listener"
extern fun _bats_js_remove_event_listener
  (listener_id: int): void = "mac#bats_js_remove_event_listener"
extern fun _bats_js_prevent_default
  (): void = "mac#bats_js_prevent_default"

(* --- Navigation --- *)
extern fun _bats_js_get_url
  (out: ptr, max_len: int): int = "mac#bats_js_get_url"
extern fun _bats_js_get_url_hash
  (out: ptr, max_len: int): int = "mac#bats_js_get_url_hash"
extern fun _bats_js_set_url_hash
  (hash: ptr, hash_len: int): void = "mac#bats_js_set_url_hash"
extern fun _bats_js_replace_state
  (url: ptr, url_len: int): void = "mac#bats_js_replace_state"
extern fun _bats_js_push_state
  (url: ptr, url_len: int): void = "mac#bats_js_push_state"

(* --- Window --- *)
extern fun _bats_js_focus_window
  (): void = "mac#bats_js_focus_window"
extern fun _bats_js_get_visibility_state
  (): int = "mac#bats_js_get_visibility_state"
extern fun _bats_js_log
  (level: int, msg: ptr, msg_len: int): void = "mac#bats_js_log"

(* --- IDB --- *)
extern fun _bats_idb_js_put
  (key: ptr, key_len: int, val_data: ptr, val_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_put"
extern fun _bats_idb_js_get
  (key: ptr, key_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_get"
extern fun _bats_idb_js_delete
  (key: ptr, key_len: int, resolver_id: int)
  : void = "mac#bats_idb_js_delete"

(* --- Fetch --- *)
extern fun _bats_js_fetch
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_fetch"

(* --- Clipboard --- *)
extern fun _bats_js_clipboard_write_text
  (text: ptr, text_len: int, resolver_id: int)
  : void = "mac#bats_js_clipboard_write_text"

(* --- File --- *)
extern fun _bats_js_file_open
  (input_node_id: int, resolver_id: int): void = "mac#bats_js_file_open"
extern fun _bats_js_file_read
  (handle: int, file_offset: int, len: int, out: ptr): int = "mac#bats_js_file_read"
extern fun _bats_js_file_close
  (handle: int): void = "mac#bats_js_file_close"

(* --- Decompress --- *)
extern fun _bats_js_decompress
  (data: ptr, data_len: int, method: int, resolver_id: int)
  : void = "mac#bats_js_decompress"
extern fun _bats_js_blob_read
  (handle: int, blob_offset: int, len: int, out: ptr): int = "mac#bats_js_blob_read"
extern fun _bats_js_blob_free
  (handle: int): void = "mac#bats_js_blob_free"

(* --- Notify --- *)
extern fun _bats_js_notification_request_permission
  (resolver_id: int): void = "mac#bats_js_notification_request_permission"
extern fun _bats_js_notification_show
  (title: ptr, title_len: int): void = "mac#bats_js_notification_show"
extern fun _bats_js_push_subscribe
  (vapid: ptr, vapid_len: int, resolver_id: int)
  : void = "mac#bats_js_push_subscribe"
extern fun _bats_js_push_get_subscription
  (resolver_id: int): void = "mac#bats_js_push_get_subscription"

(* --- XML --- *)
extern fun _bats_js_parse_html
  (html: ptr, len: int): int = "mac#bats_js_parse_html"

(* --- Stash --- *)
extern fun _bats_js_stash_read
  (stash_id: int, dest: ptr, len: int): void = "mac#bats_js_stash_read"

(* ============================================================
   Internal helper -- allocate + fill from JS stash
   ============================================================ *)

fun _bridge_recv{n:pos | n <= 1048576}
  (stash_id: int, len: int n): [l:agz] $A.arr(byte, l, n) = let
  val buf = $A.alloc<byte>(len)
  val p = $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buf) end
  val () = _bats_js_stash_read(stash_id, p, len)
in buf end

fn _stash_get_int(slot: int): int =
  $extfcall(int, "bats_bridge_stash_get_int", slot)

fn _stash_set_int(slot: int, v: int): void =
  $extfcall(void, "bats_bridge_stash_set_int", slot, v)

(* ============================================================
   Implementations
   ============================================================ *)

(* --- Timer --- *)

implement timer_set(delay_ms, stash_id) =
  _bats_set_timer(delay_ms, stash_id)

implement exit() = _bats_exit()

(* --- DOM --- *)

implement dom_flush{l}{n}{m}(buf, len) =
  _bats_dom_flush(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buf) end,
    len)

implement set_image_src{ld}{nd}{lm}{nm}
  (node_id, data, data_len, mime, mime_len) =
  _bats_js_set_image_src(node_id,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, data_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len)

(* --- DOM read --- *)

implement measure(node_id) = let
  val r = _bats_js_measure_node(node_id)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement get_measure_x() = $extfcall(int, "_bridge_measure_get", 0)
implement get_measure_y() = $extfcall(int, "_bridge_measure_get", 1)
implement get_measure_w() = $extfcall(int, "_bridge_measure_get", 2)
implement get_measure_h() = $extfcall(int, "_bridge_measure_get", 3)
implement get_measure_scroll_w() = $extfcall(int, "_bridge_measure_get", 4)
implement get_measure_scroll_h() = $extfcall(int, "_bridge_measure_get", 5)

implement query_selector{lb}{n}(sel, sel_len) = let
  val r = _bats_js_query_selector(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(sel) end,
    sel_len)
in
  if r >= 0 then $R.some(r) else $R.none()
end

(* --- Event --- *)

implement listen{lb}{n}(node_id, event_type, type_len, listener_id) =
  _bats_js_add_event_listener(node_id,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id)

implement unlisten(listener_id) =
  _bats_js_remove_event_listener(listener_id)

implement prevent_default() = _bats_js_prevent_default()

implement listener_set(id, cb) =
  $extfcall(void, "bats_listener_set", id, cb)

implement listener_set_closure(id, cb) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(cb) end
in $extfcall(void, "bats_listener_set", id, cbp) end

implement listener_clear(id) =
  $extfcall(void, "bats_listener_set", id, the_null_ptr)

implement listener_get(id) =
  $extfcall(ptr, "bats_listener_get", id)

(* --- Navigation --- *)

implement get_url{l}{n}(out, max_len) = let
  val r = _bats_js_get_url(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement get_hash{l}{n}(out, max_len) = let
  val r = _bats_js_get_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement set_hash{lb}{n}(hash, hash_len) =
  _bats_js_set_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(hash) end,
    hash_len)

implement replace_state{lb}{n}(url, url_len) =
  _bats_js_replace_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

implement push_state{lb}{n}(url, url_len) =
  _bats_js_push_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

(* --- Window --- *)

implement focus() = _bats_js_focus_window()

implement get_visibility() = _bats_js_get_visibility_state()

implement log{lb}{n}(level, msg, msg_len) =
  _bats_js_log(level,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(msg) end,
    msg_len)

(* --- IDB --- *)

implement idb_put{lk}{nk}{lv}{nv}
  (key, key_len, val_data, val_len, stash_id) =
  _bats_idb_js_put(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(val_data) end, val_len,
    stash_id)

implement idb_get{lk}{nk}(key, key_len, stash_id) =
  _bats_idb_js_get(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    stash_id)

implement idb_get_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement idb_delete{lk}{nk}(key, key_len, stash_id) =
  _bats_idb_js_delete(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    stash_id)

(* --- Fetch --- *)

implement fetch_req{lb}{n}(url, url_len, stash_id) =
  _bats_js_fetch(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    stash_id)

implement fetch_body_len() = _stash_get_int(0)

implement fetch_body{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

(* --- Clipboard --- *)

implement clipboard_write{lb}{n}(text, text_len, stash_id) =
  _bats_js_clipboard_write_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    stash_id)

(* --- File --- *)

implement file_open(input_node_id, stash_id) =
  _bats_js_file_open(input_node_id, stash_id)

implement file_size() = _stash_get_int(0)

implement file_name_len() = _stash_get_int(2)

implement file_name{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement file_read{l}{n}(handle, file_offset, out, len) = let
  val r = _bats_js_file_read(handle, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement file_close(handle) = _bats_js_file_close(handle)

(* --- Decompress --- *)

implement decompress_req{lb}{n}(data, data_len, method, stash_id) =
  _bats_js_decompress(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end,
    data_len, method, stash_id)

implement decompress_len() = _stash_get_int(0)

implement blob_read{l}{n}(handle, blob_offset, out, len) = let
  val r = _bats_js_blob_read(handle, blob_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement blob_free(handle) = _bats_js_blob_free(handle)

(* --- Notify --- *)

implement notify_request(stash_id) =
  _bats_js_notification_request_permission(stash_id)

implement notify_show{lb}{n}(title, title_len) =
  _bats_js_notification_show(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end,
    title_len)

implement notify_subscribe{lb}{n}(vapid, vapid_len, stash_id) =
  _bats_js_push_subscribe(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(vapid) end,
    vapid_len, stash_id)

implement notify_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement notify_get_sub(stash_id) =
  _bats_js_push_get_subscription(stash_id)

(* --- XML --- *)

implement xml_parse{lb}{n}(html, len) =
  _bats_js_parse_html(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(html) end,
    len)

implement xml_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

(* --- Stash --- *)

implement stash_read{n}(stash_id, len) =
  _bridge_recv(stash_id, len)

implement stash_set_int(slot, v0) = _stash_set_int(slot, v0)

implement stash_get_int(slot) = _stash_get_int(slot)

(* --- WASM exports --- *)

implement on_timer_fire(resolver_id) =
  $P.fire(resolver_id, 0)

implement on_event(listener_id, payload_len) = let
  val cbp = $extfcall(ptr, "bats_listener_get", listener_id)
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE begin $UNSAFE.cast{(int) -<cloref1> int}(cbp) end
    val _ = cb(payload_len)
  in () end
  else ()
end

implement on_fetch_complete(resolver_id, status, body_len) = let
  val () = _stash_set_int(0, body_len)
in $P.fire(resolver_id, status) end

implement on_clipboard_complete(resolver_id, success) =
  $P.fire(resolver_id, success)

implement on_file_open(resolver_id, handle, size) = let
  val () = _stash_set_int(0, size)
in $P.fire(resolver_id, handle) end

implement on_decompress_complete(resolver_id, handle, decompressed_len) = let
  val () = _stash_set_int(0, decompressed_len)
in $P.fire(resolver_id, handle) end

implement on_idb_fire(resolver_id, status) =
  $P.fire(resolver_id, status)

implement on_idb_fire_get(resolver_id, data_len) =
  $P.fire(resolver_id, data_len)

implement on_permission_result(resolver_id, granted) =
  $P.fire(resolver_id, granted)

implement on_push_subscribe(resolver_id, json_len) =
  $P.fire(resolver_id, json_len)

end
