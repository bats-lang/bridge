(* bridge -- centralized WASM host import wrappers for bats *)
(* No other package touches $UNSAFE or declares extern WASM imports. *)
(* Bridge exports safe #pub fun wrappers over all mac# host calls. *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   C runtime -- stash, measure, listener tables + WASM exports
   ============================================================ *)

$UNSAFE begin
%{#
/* Bridge int stash -- 4 slots for stash IDs and metadata */
static int _bridge_stash_int[4] = {0};

void ward_bridge_stash_set_int(int slot, int v) {
  _bridge_stash_int[slot] = v;
}

int ward_bridge_stash_get_int(int slot) {
  return _bridge_stash_int[slot];
}

/* Measure stash -- 6 slots for x, y, w, h, scrollW, scrollH */
static int _bridge_measure[6] = {0};

void ward_measure_set(int slot, int v) {
  _bridge_measure[slot] = v;
}

static int _bridge_measure_get(int slot) {
  return _bridge_measure[slot];
}

/* Listener table -- max 128 */
#define _BRIDGE_MAX_LISTENERS 128
static void *_bridge_listener_table[_BRIDGE_MAX_LISTENERS] = {0};

void ward_listener_set(int id, void *cb) {
  if (id >= 0 && id < _BRIDGE_MAX_LISTENERS) _bridge_listener_table[id] = cb;
}

void *ward_listener_get(int id) {
  if (id >= 0 && id < _BRIDGE_MAX_LISTENERS) return _bridge_listener_table[id];
  return (void*)0;
}

/* JS-side data stash read import */
static void _bridge_stash_read(int stash_id, void *dest, int len);
%}
end

(* ============================================================
   Internal -- extern WASM imports (all mac# declarations)
   ============================================================ *)

(* --- Timer --- *)
extern fun _ward_set_timer
  (delay_ms: int, resolver_id: int): void = "mac#ward_set_timer"
extern fun _ward_exit
  (): void = "mac#ward_exit"

(* --- DOM --- *)
extern fun _ward_dom_flush
  (buf: ptr, len: int): void = "mac#ward_dom_flush"
extern fun _ward_js_set_image_src
  (node_id: int, data: ptr, data_len: int, mime: ptr, mime_len: int)
  : void = "mac#ward_js_set_image_src"

(* --- DOM read --- *)
extern fun _ward_js_measure_node
  (node_id: int): int = "mac#ward_js_measure_node"
extern fun _ward_js_query_selector
  (selector: ptr, selector_len: int): int = "mac#ward_js_query_selector"

(* --- Event --- *)
extern fun _ward_js_add_event_listener
  (node_id: int, event_type: ptr, type_len: int, listener_id: int)
  : void = "mac#ward_js_add_event_listener"
extern fun _ward_js_remove_event_listener
  (listener_id: int): void = "mac#ward_js_remove_event_listener"
extern fun _ward_js_prevent_default
  (): void = "mac#ward_js_prevent_default"

(* --- Navigation --- *)
extern fun _ward_js_get_url
  (out: ptr, max_len: int): int = "mac#ward_js_get_url"
extern fun _ward_js_get_url_hash
  (out: ptr, max_len: int): int = "mac#ward_js_get_url_hash"
extern fun _ward_js_set_url_hash
  (hash: ptr, hash_len: int): void = "mac#ward_js_set_url_hash"
extern fun _ward_js_replace_state
  (url: ptr, url_len: int): void = "mac#ward_js_replace_state"
extern fun _ward_js_push_state
  (url: ptr, url_len: int): void = "mac#ward_js_push_state"

(* --- Window --- *)
extern fun _ward_js_focus_window
  (): void = "mac#ward_js_focus_window"
extern fun _ward_js_get_visibility_state
  (): int = "mac#ward_js_get_visibility_state"
extern fun _ward_js_log
  (level: int, msg: ptr, msg_len: int): void = "mac#ward_js_log"

(* --- IDB --- *)
extern fun _ward_idb_js_put
  (key: ptr, key_len: int, val_data: ptr, val_len: int, resolver_id: int)
  : void = "mac#ward_idb_js_put"
extern fun _ward_idb_js_get
  (key: ptr, key_len: int, resolver_id: int)
  : void = "mac#ward_idb_js_get"
extern fun _ward_idb_js_delete
  (key: ptr, key_len: int, resolver_id: int)
  : void = "mac#ward_idb_js_delete"

(* --- Fetch --- *)
extern fun _ward_js_fetch
  (url: ptr, url_len: int, resolver_id: int): void = "mac#ward_js_fetch"

(* --- Clipboard --- *)
extern fun _ward_js_clipboard_write_text
  (text: ptr, text_len: int, resolver_id: int)
  : void = "mac#ward_js_clipboard_write_text"

(* --- File --- *)
extern fun _ward_js_file_open
  (input_node_id: int, resolver_id: int): void = "mac#ward_js_file_open"
extern fun _ward_js_file_read
  (handle: int, file_offset: int, len: int, out: ptr): int = "mac#ward_js_file_read"
extern fun _ward_js_file_close
  (handle: int): void = "mac#ward_js_file_close"

(* --- Decompress --- *)
extern fun _ward_js_decompress
  (data: ptr, data_len: int, method: int, resolver_id: int)
  : void = "mac#ward_js_decompress"
extern fun _ward_js_blob_read
  (handle: int, blob_offset: int, len: int, out: ptr): int = "mac#ward_js_blob_read"
extern fun _ward_js_blob_free
  (handle: int): void = "mac#ward_js_blob_free"

(* --- Notify --- *)
extern fun _ward_js_notification_request_permission
  (resolver_id: int): void = "mac#ward_js_notification_request_permission"
extern fun _ward_js_notification_show
  (title: ptr, title_len: int): void = "mac#ward_js_notification_show"
extern fun _ward_js_push_subscribe
  (vapid: ptr, vapid_len: int, resolver_id: int)
  : void = "mac#ward_js_push_subscribe"
extern fun _ward_js_push_get_subscription
  (resolver_id: int): void = "mac#ward_js_push_get_subscription"

(* --- XML --- *)
extern fun _ward_js_parse_html
  (html: ptr, len: int): int = "mac#ward_js_parse_html"

(* --- Stash --- *)
extern fun _ward_js_stash_read
  (stash_id: int, dest: ptr, len: int): void = "mac#ward_js_stash_read"

(* ============================================================
   Internal helper -- allocate + fill from JS stash
   ============================================================ *)

fun _bridge_recv{n:pos | n <= 1048576}
  (stash_id: int, len: int n): [l:agz] $A.arr(byte, l, n) = let
  val buf = $A.alloc<byte>(len)
  val p = $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buf) end
  val () = _ward_js_stash_read(stash_id, p, len)
in buf end

fn _stash_get_int(slot: int): int =
  $extfcall(int, "ward_bridge_stash_get_int", slot)

fn _stash_set_int(slot: int, v: int): void =
  $extfcall(void, "ward_bridge_stash_set_int", slot, v)

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
  (node_id: int): int

#pub fun get_measure_x(): int

#pub fun get_measure_y(): int

#pub fun get_measure_w(): int

#pub fun get_measure_h(): int

#pub fun get_measure_scroll_w(): int

#pub fun get_measure_scroll_h(): int

#pub fun query_selector
  {lb:agz}{n:pos}
  (sel: !$A.borrow(byte, lb, n), sel_len: int n): int

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

#pub fun listener_get
  (id: int): ptr

(* --- Navigation --- *)

#pub fun get_url
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): int

#pub fun get_hash
  {l:agz}{n:pos}
  (out: !$A.arr(byte, l, n), max_len: int n): int

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
   out: !$A.arr(byte, l, n), len: int n): int

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
   out: !$A.arr(byte, l, n), len: int n): int

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
  (resolver_id: int): void = "ext#ward_timer_fire"

#pub fun on_event
  (listener_id: int, payload_len: int): void = "ext#ward_on_event"

#pub fun on_fetch_complete
  (resolver_id: int, status: int, body_len: int): void = "ext#ward_on_fetch_complete"

#pub fun on_clipboard_complete
  (resolver_id: int, success: int): void = "ext#ward_on_clipboard_complete"

#pub fun on_file_open
  (resolver_id: int, handle: int, size: int): void = "ext#ward_on_file_open"

#pub fun on_decompress_complete
  (resolver_id: int, handle: int, decompressed_len: int)
  : void = "ext#ward_on_decompress_complete"

#pub fun on_idb_fire
  (resolver_id: int, status: int): void = "ext#ward_idb_fire"

#pub fun on_idb_fire_get
  (resolver_id: int, data_len: int): void = "ext#ward_idb_fire_get"

#pub fun on_permission_result
  (resolver_id: int, granted: int): void = "ext#ward_on_permission_result"

#pub fun on_push_subscribe
  (resolver_id: int, json_len: int): void = "ext#ward_on_push_subscribe"

(* ============================================================
   produce_bridge -- returns the complete JS bridge as a string
   ============================================================ *)

#pub fun produce_bridge(): string

(* ============================================================
   Implementations
   ============================================================ *)

(* --- Timer --- *)

implement timer_set(delay_ms, stash_id) =
  _ward_set_timer(delay_ms, stash_id)

implement exit() = _ward_exit()

(* --- DOM --- *)

implement dom_flush{l}{n}{m}(buf, len) =
  _ward_dom_flush(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buf) end,
    len)

implement set_image_src{ld}{nd}{lm}{nm}
  (node_id, data, data_len, mime, mime_len) =
  _ward_js_set_image_src(node_id,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, data_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len)

(* --- DOM read --- *)

implement measure(node_id) = _ward_js_measure_node(node_id)

implement get_measure_x() = $extfcall(int, "_bridge_measure_get", 0)
implement get_measure_y() = $extfcall(int, "_bridge_measure_get", 1)
implement get_measure_w() = $extfcall(int, "_bridge_measure_get", 2)
implement get_measure_h() = $extfcall(int, "_bridge_measure_get", 3)
implement get_measure_scroll_w() = $extfcall(int, "_bridge_measure_get", 4)
implement get_measure_scroll_h() = $extfcall(int, "_bridge_measure_get", 5)

implement query_selector{lb}{n}(sel, sel_len) =
  _ward_js_query_selector(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(sel) end,
    sel_len)

(* --- Event --- *)

implement listen{lb}{n}(node_id, event_type, type_len, listener_id) =
  _ward_js_add_event_listener(node_id,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(event_type) end,
    type_len, listener_id)

implement unlisten(listener_id) =
  _ward_js_remove_event_listener(listener_id)

implement prevent_default() = _ward_js_prevent_default()

implement listener_set(id, cb) =
  $extfcall(void, "ward_listener_set", id, cb)

implement listener_get(id) =
  $extfcall(ptr, "ward_listener_get", id)

(* --- Navigation --- *)

implement get_url{l}{n}(out, max_len) =
  _ward_js_get_url(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)

implement get_hash{l}{n}(out, max_len) =
  _ward_js_get_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end,
    max_len)

implement set_hash{lb}{n}(hash, hash_len) =
  _ward_js_set_url_hash(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(hash) end,
    hash_len)

implement replace_state{lb}{n}(url, url_len) =
  _ward_js_replace_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

implement push_state{lb}{n}(url, url_len) =
  _ward_js_push_state(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end,
    url_len)

(* --- Window --- *)

implement focus() = _ward_js_focus_window()

implement get_visibility() = _ward_js_get_visibility_state()

implement log{lb}{n}(level, msg, msg_len) =
  _ward_js_log(level,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(msg) end,
    msg_len)

(* --- IDB --- *)

implement idb_put{lk}{nk}{lv}{nv}
  (key, key_len, val_data, val_len, stash_id) =
  _ward_idb_js_put(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(val_data) end, val_len,
    stash_id)

implement idb_get{lk}{nk}(key, key_len, stash_id) =
  _ward_idb_js_get(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    stash_id)

implement idb_get_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement idb_delete{lk}{nk}(key, key_len, stash_id) =
  _ward_idb_js_delete(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(key) end, key_len,
    stash_id)

(* --- Fetch --- *)

implement fetch_req{lb}{n}(url, url_len, stash_id) =
  _ward_js_fetch(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    stash_id)

implement fetch_body_len() = _stash_get_int(0)

implement fetch_body{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

(* --- Clipboard --- *)

implement clipboard_write{lb}{n}(text, text_len, stash_id) =
  _ward_js_clipboard_write_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    stash_id)

(* --- File --- *)

implement file_open(input_node_id, stash_id) =
  _ward_js_file_open(input_node_id, stash_id)

implement file_size() = _stash_get_int(0)

implement file_name_len() = _stash_get_int(2)

implement file_name{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement file_read{l}{n}(handle, file_offset, out, len) =
  _ward_js_file_read(handle, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)

implement file_close(handle) = _ward_js_file_close(handle)

(* --- Decompress --- *)

implement decompress_req{lb}{n}(data, data_len, method, stash_id) =
  _ward_js_decompress(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end,
    data_len, method, stash_id)

implement decompress_len() = _stash_get_int(0)

implement blob_read{l}{n}(handle, blob_offset, out, len) =
  _ward_js_blob_read(handle, blob_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)

implement blob_free(handle) = _ward_js_blob_free(handle)

(* --- Notify --- *)

implement notify_request(stash_id) =
  _ward_js_notification_request_permission(stash_id)

implement notify_show{lb}{n}(title, title_len) =
  _ward_js_notification_show(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end,
    title_len)

implement notify_subscribe{lb}{n}(vapid, vapid_len, stash_id) =
  _ward_js_push_subscribe(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(vapid) end,
    vapid_len, stash_id)

implement notify_result{n}(len) =
  _bridge_recv(_stash_get_int(1), len)

implement notify_get_sub(stash_id) =
  _ward_js_push_get_subscription(stash_id)

(* --- XML --- *)

implement xml_parse{lb}{n}(html, len) =
  _ward_js_parse_html(
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
  val cbp = $extfcall(ptr, "ward_listener_get", listener_id)
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


(* ============================================================
   produce_bridge -- JS bridge via C string constant
   ============================================================ *)

$UNSAFE begin
%{
static const char *_bridge_js_source(void);
%}
end

extern fun _bridge_js_source(): string = "mac#_bridge_js_source"

implement produce_bridge() = _bridge_js_source()

$UNSAFE begin
%{$
static const char *_bridge_js_source(void) {
  return
"// ward_bridge.mjs — Bridge between ward WASM and a DOM document\n"
"// Parses the ward binary diff protocol and applies it to a standard DOM.\n"
"// Works in any ES module environment (browser or Node.js).\n"
"\n"
"// Parse a little-endian i32 from a Uint8Array at offset\n"
"function readI32(buf, off) {\n"
"  return buf[off] | (buf[off+1] << 8) | (buf[off+2] << 16) | (buf[off+3] << 24);\n"
"}\n"
"\n"
"/**\n"
" * Load a ward WASM module and connect it to a DOM document.\n"
" *\n"
" * @param {BufferSource} wasmBytes — compiled WASM bytes\n"
" * @param {Element} root — root element for ward to render into (node_id 0)\n"
" * @returns {{ exports, nodes, done }} — WASM exports, node registry,\n"
" *   and a promise that resolves when WASM calls ward_exit\n"
" */\n"
"export async function loadWard(wasmBytes, root, opts) {\n"
"  const extraImports = (opts && opts.extraImports) || {};\n"
"  const document = root.ownerDocument;\n"
"  let instance = null;\n"
"  let resolveDone;\n"
"  const done = new Promise(r => { resolveDone = r; });\n"
"\n"
"  // Node registry: node_id -> DOM element\n"
"  const nodes = new Map();\n"
"  nodes.set(0, root);\n"
"\n"
"  function readBytes(ptr, len) {\n"
"    return new Uint8Array(instance.exports.memory.buffer, ptr, len).slice();\n"
"  }\n"
"\n"
"  function readString(ptr, len) {\n"
"    return new TextDecoder().decode(readBytes(ptr, len));\n"
"  }\n"
"\n"
"  // JS-side data stash — WASM pulls data via ward_js_stash_read\n"
"  const dataStash = new Map();\n"
"  let nextStashId = 0;\n"
"\n"
"  function stashData(data) {\n"
"    const id = nextStashId++;\n"
"    dataStash.set(id, data);\n"
"    return id;\n"
"  }\n"
"\n"
"  function wardJsStashRead(stashId, destPtr, len) {\n"
"    const data = dataStash.get(stashId);\n"
"    if (data) {\n"
"      const copyLen = Math.min(len, data.length);\n"
"      new Uint8Array(instance.exports.memory.buffer).set(\n"
"        data.subarray(0, copyLen), destPtr);\n"
"      dataStash.delete(stashId);\n"
"    }\n"
"  }\n"
"\n"
"  // Blob URL lifecycle tracking — revoked when element gets new image or is removed\n"
"  const blobUrls = new Map();\n"
"\n"
"  // --- DOM helpers ---\n"
"\n"
"  // Remove all descendant entries from `nodes` and revoke their blob URLs.\n"
"  // Called before clearing or removing an element that may have registered children.\n"
"  function cleanDescendants(parentEl) {\n"
"    for (const [id, node] of nodes) {\n"
"      if (id !== 0 && node !== parentEl && parentEl.contains(node)) {\n"
"        const oldUrl = blobUrls.get(id);\n"
"        if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(id); }\n"
"        nodes.delete(id);\n"
"      }\n"
"    }\n"
"  }\n"
"\n"
"  // --- DOM flush ---\n"
"\n"
"  function wardDomFlush(bufPtr, len) {\n"
"    const mem = new Uint8Array(instance.exports.memory.buffer);\n"
"    let pos = 0;\n"
"\n"
"    while (pos < len) {\n"
"      const op = mem[bufPtr + pos];\n"
"      const nodeId = readI32(mem, bufPtr + pos + 1);\n"
"\n"
"      switch (op) {\n"
"        case 4: { // CREATE_ELEMENT\n"
"          const parentId = readI32(mem, bufPtr + pos + 5);\n"
"          const tagLen = mem[bufPtr + pos + 9];\n"
"          const tag = new TextDecoder().decode(mem.slice(bufPtr + pos + 10, bufPtr + pos + 10 + tagLen));\n"
"          const el = document.createElement(tag);\n"
"          nodes.set(nodeId, el);\n"
"          const parent = nodes.get(parentId);\n"
"          if (parent) parent.appendChild(el);\n"
"          pos += 10 + tagLen;\n"
"          break;\n"
"        }\n"
"        case 1: { // SET_TEXT\n"
"          const textLen = mem[bufPtr + pos + 5] | (mem[bufPtr + pos + 6] << 8);\n"
"          const text = new TextDecoder().decode(mem.slice(bufPtr + pos + 7, bufPtr + pos + 7 + textLen));\n"
"          const el = nodes.get(nodeId);\n"
"          if (el) el.textContent = text;\n"
"          pos += 7 + textLen;\n"
"          break;\n"
"        }\n"
"        case 2: { // SET_ATTR\n"
"          const nameLen = mem[bufPtr + pos + 5];\n"
"          const name = new TextDecoder().decode(mem.slice(bufPtr + pos + 6, bufPtr + pos + 6 + nameLen));\n"
"          const valOff = pos + 6 + nameLen;\n"
"          const valLen = mem[bufPtr + valOff] | (mem[bufPtr + valOff + 1] << 8);\n"
"          const value = new TextDecoder().decode(mem.slice(bufPtr + valOff + 2, bufPtr + valOff + 2 + valLen));\n"
"          const el = nodes.get(nodeId);\n"
"          if (el) el.setAttribute(name, value);\n"
"          pos += 6 + nameLen + 2 + valLen;\n"
"          break;\n"
"        }\n"
"        case 3: { // REMOVE_CHILDREN\n"
"          const el = nodes.get(nodeId);\n"
"          if (el) {\n"
"            cleanDescendants(el);\n"
"            el.innerHTML = '';\n"
"          }\n"
"          pos += 5;\n"
"          break;\n"
"        }\n"
"        case 5: { // REMOVE_CHILD\n"
"          const el = nodes.get(nodeId);\n"
"          if (el) {\n"
"            cleanDescendants(el);\n"
"            el.remove();\n"
"          }\n"
"          const oldUrl = blobUrls.get(nodeId);\n"
"          if (oldUrl) { URL.revokeObjectURL(oldUrl); blobUrls.delete(nodeId); }\n"
"          nodes.delete(nodeId);\n"
"          pos += 5;\n"
"          break;\n"
"        }\n"
"        default:\n"
"          throw new Error(`Unknown ward DOM op: ${op} at offset ${pos}`);\n"
"      }\n"
"    }\n"
"  }\n"
"\n"
"  // --- Image src (direct bridge call, not diff buffer) ---\n"
"\n"
"  function wardJsSetImageSrc(nodeId, dataPtr, dataLen, mimePtr, mimeLen) {\n"
"    const mime = readString(mimePtr, mimeLen);\n"
"    const bytes = readBytes(dataPtr, dataLen);\n"
"    const oldUrl = blobUrls.get(nodeId);\n"
"    if (oldUrl) URL.revokeObjectURL(oldUrl);\n"
"    const blob = new Blob([bytes], { type: mime });\n"
"    const url = URL.createObjectURL(blob);\n"
"    const el = nodes.get(nodeId);\n"
"    if (el) el.src = url;\n"
"    blobUrls.set(nodeId, url);\n"
"  }\n"
"\n"
"  // --- Timer ---\n"
"\n"
"  function wardSetTimer(delayMs, resolverId) {\n"
"    setTimeout(() => {\n"
"      instance.exports.ward_timer_fire(resolverId);\n"
"    }, delayMs);\n"
"  }\n"
"\n"
"  // --- IndexedDB ---\n"
"\n"
"  let dbPromise = null;\n"
"  function openDB() {\n"
"    if (!dbPromise) {\n"
"      dbPromise = new Promise((resolve, reject) => {\n"
"        const req = indexedDB.open('ward', 1);\n"
"        req.onupgradeneeded = () => {\n"
"          req.result.createObjectStore('kv');\n"
"        };\n"
"        req.onsuccess = () => resolve(req.result);\n"
"        req.onerror = () => reject(req.error);\n"
"      });\n"
"    }\n"
"    return dbPromise;\n"
"  }\n"
"\n"
"  function wardIdbPut(keyPtr, keyLen, valPtr, valLen, resolverId) {\n"
"    const key = readString(keyPtr, keyLen);\n"
"    const val = readBytes(valPtr, valLen);\n"
"    openDB().then(db => {\n"
"      const tx = db.transaction('kv', 'readwrite');\n"
"      tx.objectStore('kv').put(val, key);\n"
"      tx.oncomplete = () => {\n"
"        instance.exports.ward_idb_fire(resolverId, 0);\n"
"      };\n"
"      tx.onerror = () => {\n"
"        instance.exports.ward_idb_fire(resolverId, -1);\n"
"      };\n"
"    });\n"
"  }\n"
"\n"
"  function wardIdbGet(keyPtr, keyLen, resolverId) {\n"
"    const key = readString(keyPtr, keyLen);\n"
"    openDB().then(db => {\n"
"      const tx = db.transaction('kv', 'readonly');\n"
"      const req = tx.objectStore('kv').get(key);\n"
"      req.onsuccess = () => {\n"
"        const result = req.result;\n"
"        if (result === undefined) {\n"
"          instance.exports.ward_idb_fire_get(resolverId, 0);\n"
"        } else {\n"
"          const data = new Uint8Array(result);\n"
"          const stashId = stashData(data);\n"
"          instance.exports.ward_bridge_stash_set_int(1, stashId);\n"
"          instance.exports.ward_idb_fire_get(resolverId, data.length);\n"
"        }\n"
"      };\n"
"      req.onerror = () => {\n"
"        instance.exports.ward_idb_fire_get(resolverId, 0);\n"
"      };\n"
"    });\n"
"  }\n"
"\n"
"  function wardIdbDelete(keyPtr, keyLen, resolverId) {\n"
"    const key = readString(keyPtr, keyLen);\n"
"    openDB().then(db => {\n"
"      const tx = db.transaction('kv', 'readwrite');\n"
"      tx.objectStore('kv').delete(key);\n"
"      tx.oncomplete = () => {\n"
"        instance.exports.ward_idb_fire(resolverId, 0);\n"
"      };\n"
"      tx.onerror = () => {\n"
"        instance.exports.ward_idb_fire(resolverId, -1);\n"
"      };\n"
"    });\n"
"  }\n"
"\n"
"  // --- Window ---\n"
"\n"
"  function wardJsFocusWindow() {\n"
"    try { root.ownerDocument.defaultView.focus(); } catch(e) {}\n"
"  }\n"
"\n"
"  function wardJsGetVisibilityState() {\n"
"    try {\n"
"      return document.visibilityState === 'hidden' ? 1 : 0;\n"
"    } catch(e) { return 0; }\n"
"  }\n"
"\n"
"  function wardJsLog(level, msgPtr, msgLen) {\n"
"    const msg = readString(msgPtr, msgLen);\n"
"    const labels = ['debug', 'info', 'warn', 'error'];\n"
"    const label = labels[level] || 'log';\n"
"    console.log(`[ward:${label}] ${msg}`);\n"
"  }\n"
"\n"
"  // --- Navigation ---\n"
"\n"
"  function writeStringToWasm(str, outPtr, maxLen) {\n"
"    const encoded = new TextEncoder().encode(str);\n"
"    const len = Math.min(encoded.length, maxLen);\n"
"    new Uint8Array(instance.exports.memory.buffer).set(encoded.subarray(0, len), outPtr);\n"
"    return len;\n"
"  }\n"
"\n"
"  function wardJsGetUrl(outPtr, maxLen) {\n"
"    try {\n"
"      const win = root.ownerDocument.defaultView;\n"
"      return writeStringToWasm(win.location.href, outPtr, maxLen);\n"
"    } catch(e) { return 0; }\n"
"  }\n"
"\n"
"  function wardJsGetUrlHash(outPtr, maxLen) {\n"
"    try {\n"
"      const win = root.ownerDocument.defaultView;\n"
"      return writeStringToWasm(win.location.hash, outPtr, maxLen);\n"
"    } catch(e) { return 0; }\n"
"  }\n"
"\n"
"  function wardJsSetUrlHash(hashPtr, hashLen) {\n"
"    try {\n"
"      const win = root.ownerDocument.defaultView;\n"
"      win.location.hash = readString(hashPtr, hashLen);\n"
"    } catch(e) {}\n"
"  }\n"
"\n"
"  function wardJsReplaceState(urlPtr, urlLen) {\n"
"    try {\n"
"      const win = root.ownerDocument.defaultView;\n"
"      win.history.replaceState(null, '', readString(urlPtr, urlLen));\n"
"    } catch(e) {}\n"
"  }\n"
"\n"
"  function wardJsPushState(urlPtr, urlLen) {\n"
"    try {\n"
"      const win = root.ownerDocument.defaultView;\n"
"      win.history.pushState(null, '', readString(urlPtr, urlLen));\n"
"    } catch(e) {}\n"
"  }\n"
"\n"
"  // --- DOM read ---\n"
"\n"
"  function wardJsMeasureNode(nodeId) {\n"
"    const el = nodes.get(nodeId);\n"
"    if (el && typeof el.getBoundingClientRect === 'function') {\n"
"      const rect = el.getBoundingClientRect();\n"
"      instance.exports.ward_measure_set(0, Math.round(rect.x));\n"
"      instance.exports.ward_measure_set(1, Math.round(rect.y));\n"
"      instance.exports.ward_measure_set(2, Math.round(rect.width));\n"
"      instance.exports.ward_measure_set(3, Math.round(rect.height));\n"
"      instance.exports.ward_measure_set(4, el.scrollWidth || 0);\n"
"      instance.exports.ward_measure_set(5, el.scrollHeight || 0);\n"
"      return 1;\n"
"    }\n"
"    for (let i = 0; i < 6; i++) {\n"
"      instance.exports.ward_measure_set(i, 0);\n"
"    }\n"
"    return 0;\n"
"  }\n"
"\n"
"  function wardJsQuerySelector(selectorPtr, selectorLen) {\n"
"    const selector = readString(selectorPtr, selectorLen);\n"
"    try {\n"
"      const el = document.querySelector(selector);\n"
"      if (!el) return -1;\n"
"      for (const [id, node] of nodes) {\n"
"        if (node === el) return id;\n"
"      }\n"
"      return -1;\n"
"    } catch(e) { return -1; }\n"
"  }\n"
"\n"
"  // --- Event listener ---\n"
"\n"
"  const listenerMap = new Map();\n"
"  let currentEvent = null;\n"
"\n"
"  // Encode event payload as binary (little-endian).\n"
"  // Returns Uint8Array or null for no payload.\n"
"  function encodeEventPayload(event, eventType) {\n"
"    if (eventType === 'click' || eventType === 'pointerdown' ||\n"
"        eventType === 'pointerup' || eventType === 'pointermove') {\n"
"      // [f64:clientX] [f64:clientY] [i32:target_node_id]\n"
"      const buf = new ArrayBuffer(20);\n"
"      const dv = new DataView(buf);\n"
"      dv.setFloat64(0, event.clientX || 0, true);\n"
"      dv.setFloat64(8, event.clientY || 0, true);\n"
"      let targetId = -1;\n"
"      if (event.target) {\n"
"        for (const [id, node] of nodes) {\n"
"          if (node === event.target) { targetId = id; break; }\n"
"        }\n"
"      }\n"
"      dv.setInt32(16, targetId, true);\n"
"      return new Uint8Array(buf);\n"
"    }\n"
"    if (eventType === 'keydown' || eventType === 'keyup') {\n"
"      // [u8:keyLen] [bytes:key] [u8:flags]\n"
"      const key = event.key || '';\n"
"      const keyBytes = new TextEncoder().encode(key);\n"
"      const buf = new Uint8Array(1 + keyBytes.length + 1);\n"
"      buf[0] = keyBytes.length;\n"
"      buf.set(keyBytes, 1);\n"
"      const flags = (event.shiftKey ? 1 : 0) | (event.ctrlKey ? 2 : 0) |\n"
"                    (event.altKey ? 4 : 0) | (event.metaKey ? 8 : 0);\n"
"      buf[1 + keyBytes.length] = flags;\n"
"      return buf;\n"
"    }\n"
"    if (eventType === 'input') {\n"
"      // [u16le:value_len] [bytes:value]\n"
"      const value = (event.target && event.target.value) || '';\n"
"      const valBytes = new TextEncoder().encode(value);\n"
"      const buf = new Uint8Array(2 + valBytes.length);\n"
"      buf[0] = valBytes.length & 0xFF;\n"
"      buf[1] = (valBytes.length >> 8) & 0xFF;\n"
"      buf.set(valBytes, 2);\n"
"      return buf;\n"
"    }\n"
"    if (eventType === 'scroll') {\n"
"      // [f64:scrollTop] [f64:scrollLeft]\n"
"      const buf = new ArrayBuffer(16);\n"
"      const dv = new DataView(buf);\n"
"      const target = event.target || {};\n"
"      dv.setFloat64(0, target.scrollTop || 0, true);\n"
"      dv.setFloat64(8, target.scrollLeft || 0, true);\n"
"      return new Uint8Array(buf);\n"
"    }\n"
"    if (eventType === 'resize') {\n"
"      // [f64:width] [f64:height]\n"
"      const buf = new ArrayBuffer(16);\n"
"      const dv = new DataView(buf);\n"
"      const win = root.ownerDocument.defaultView || {};\n"
"      dv.setFloat64(0, win.innerWidth || 0, true);\n"
"      dv.setFloat64(8, win.innerHeight || 0, true);\n"
"      return new Uint8Array(buf);\n"
"    }\n"
"    if (eventType === 'touchstart' || eventType === 'touchend' || eventType === 'touchmove') {\n"
"      // [f64:clientX] [f64:clientY] [i32:identifier]\n"
"      const touch = (event.touches && event.touches[0]) ||\n"
"                    (event.changedTouches && event.changedTouches[0]);\n"
"      if (touch) {\n"
"        const buf = new ArrayBuffer(20);\n"
"        const dv = new DataView(buf);\n"
"        dv.setFloat64(0, touch.clientX || 0, true);\n"
"        dv.setFloat64(8, touch.clientY || 0, true);\n"
"        dv.setInt32(16, touch.identifier || 0, true);\n"
"        return new Uint8Array(buf);\n"
"      }\n"
"      return null;\n"
"    }\n"
"    if (eventType === 'visibilitychange') {\n"
"      // [u8:hidden]\n"
"      return new Uint8Array([document.visibilityState === 'hidden' ? 1 : 0]);\n"
"    }\n"
"    return null;\n"
"  }\n"
"\n"
"  function wardJsAddEventListener(nodeId, eventTypePtr, typeLen, listenerId) {\n"
"    const node = nodes.get(nodeId);\n"
"    if (!node) return;\n"
"    const eventType = readString(eventTypePtr, typeLen);\n"
"    const handler = (event) => {\n"
"      currentEvent = event;\n"
"      const payload = encodeEventPayload(event, eventType);\n"
"      if (payload) {\n"
"        const stashId = stashData(payload);\n"
"        instance.exports.ward_bridge_stash_set_int(1, stashId);\n"
"      }\n"
"      instance.exports.ward_on_event(listenerId, payload ? payload.length : 0);\n"
"      currentEvent = null;\n"
"    };\n"
"    listenerMap.set(listenerId, { node, eventType, handler });\n"
"    node.addEventListener(eventType, handler);\n"
"  }\n"
"\n"
"  function wardJsRemoveEventListener(listenerId) {\n"
"    const entry = listenerMap.get(listenerId);\n"
"    if (entry) {\n"
"      entry.node.removeEventListener(entry.eventType, entry.handler);\n"
"      listenerMap.delete(listenerId);\n"
"    }\n"
"  }\n"
"\n"
"  function wardJsPreventDefault() {\n"
"    if (currentEvent) currentEvent.preventDefault();\n"
"  }\n"
"\n"
"  // --- Fetch ---\n"
"\n"
"  function wardJsFetch(urlPtr, urlLen, resolverId) {\n"
"    const url = readString(urlPtr, urlLen);\n"
"    fetch(url).then(async (response) => {\n"
"      const body = new Uint8Array(await response.arrayBuffer());\n"
"      if (body.length > 0) {\n"
"        const stashId = stashData(body);\n"
"        instance.exports.ward_bridge_stash_set_int(1, stashId);\n"
"      }\n"
"      instance.exports.ward_on_fetch_complete(resolverId, response.status, body.length);\n"
"    }).catch(() => {\n"
"      instance.exports.ward_on_fetch_complete(resolverId, 0, 0);\n"
"    });\n"
"  }\n"
"\n"
"  // --- Clipboard ---\n"
"\n"
"  function wardJsClipboardWriteText(textPtr, textLen, resolverId) {\n"
"    const text = readString(textPtr, textLen);\n"
"    try {\n"
"      const win = root.ownerDocument.defaultView;\n"
"      if (win && win.navigator && win.navigator.clipboard) {\n"
"        win.navigator.clipboard.writeText(text).then(\n"
"          () => { instance.exports.ward_on_clipboard_complete(resolverId, 1); },\n"
"          () => { instance.exports.ward_on_clipboard_complete(resolverId, 0); }\n"
"        );\n"
"      } else {\n"
"        instance.exports.ward_on_clipboard_complete(resolverId, 0);\n"
"      }\n"
"    } catch(e) {\n"
"      instance.exports.ward_on_clipboard_complete(resolverId, 0);\n"
"    }\n"
"  }\n"
"\n"
"  // --- File ---\n"
"\n"
"  const fileCache = new Map();\n"
"  let nextFileHandle = 1;\n"
"\n"
"  function wardJsFileOpen(inputNodeId, resolverId) {\n"
"    const el = nodes.get(inputNodeId);\n"
"    if (!el || !el.files || !el.files[0]) {\n"
"      instance.exports.ward_bridge_stash_set_int(2, 0);\n"
"      instance.exports.ward_on_file_open(resolverId, 0, 0);\n"
"      return;\n"
"    }\n"
"    const file = el.files[0];\n"
"    const reader = new FileReader();\n"
"    reader.onload = () => {\n"
"      const handle = nextFileHandle++;\n"
"      const data = new Uint8Array(reader.result);\n"
"      fileCache.set(handle, data);\n"
"      const nameBytes = new TextEncoder().encode(file.name);\n"
"      const nameStashId = stashData(nameBytes);\n"
"      instance.exports.ward_bridge_stash_set_int(1, nameStashId);\n"
"      instance.exports.ward_bridge_stash_set_int(2, nameBytes.length);\n"
"      instance.exports.ward_on_file_open(resolverId, handle, data.length);\n"
"    };\n"
"    reader.onerror = () => {\n"
"      instance.exports.ward_bridge_stash_set_int(2, 0);\n"
"      instance.exports.ward_on_file_open(resolverId, 0, 0);\n"
"    };\n"
"    reader.readAsArrayBuffer(file);\n"
"  }\n"
"\n"
"  function wardJsFileRead(handle, fileOffset, len, outPtr) {\n"
"    const data = fileCache.get(handle);\n"
"    if (!data) return 0;\n"
"    const available = Math.max(0, data.length - fileOffset);\n"
"    const copyLen = Math.min(len, available);\n"
"    if (copyLen > 0) {\n"
"      new Uint8Array(instance.exports.memory.buffer).set(\n"
"        data.subarray(fileOffset, fileOffset + copyLen), outPtr);\n"
"    }\n"
"    return copyLen;\n"
"  }\n"
"\n"
"  function wardJsFileClose(handle) {\n"
"    fileCache.delete(handle);\n"
"  }\n"
"\n"
"  // --- Decompress ---\n"
"\n"
"  const blobCache = new Map();\n"
"  let nextBlobHandle = 1;\n"
"\n"
"  function wardJsDecompress(dataPtr, dataLen, method, resolverId) {\n"
"    const compressed = readBytes(dataPtr, dataLen);\n"
"    const formats = ['gzip', 'deflate', 'deflate-raw'];\n"
"    const format = formats[method];\n"
"    if (!format || typeof DecompressionStream === 'undefined') {\n"
"      instance.exports.ward_on_decompress_complete(resolverId, 0, 0);\n"
"      return;\n"
"    }\n"
"    const ds = new DecompressionStream(format);\n"
"    const writer = ds.writable.getWriter();\n"
"    writer.write(compressed);\n"
"    writer.close();\n"
"    const reader = ds.readable.getReader();\n"
"    const chunks = [];\n"
"    (function pump() {\n"
"      reader.read().then(({ done, value }) => {\n"
"        if (value) chunks.push(value);\n"
"        if (done) {\n"
"          let totalLen = 0;\n"
"          for (const c of chunks) totalLen += c.length;\n"
"          const result = new Uint8Array(totalLen);\n"
"          let off = 0;\n"
"          for (const c of chunks) { result.set(c, off); off += c.length; }\n"
"          const handle = nextBlobHandle++;\n"
"          blobCache.set(handle, result);\n"
"          instance.exports.ward_on_decompress_complete(resolverId, handle, result.length);\n"
"        } else {\n"
"          pump();\n"
"        }\n"
"      }).catch(() => {\n"
"        instance.exports.ward_on_decompress_complete(resolverId, 0, 0);\n"
"      });\n"
"    })();\n"
"  }\n"
"\n"
"  function wardJsBlobRead(handle, blobOffset, len, outPtr) {\n"
"    const data = blobCache.get(handle);\n"
"    if (!data) return 0;\n"
"    const available = Math.max(0, data.length - blobOffset);\n"
"    const copyLen = Math.min(len, available);\n"
"    if (copyLen > 0) {\n"
"      new Uint8Array(instance.exports.memory.buffer).set(\n"
"        data.subarray(blobOffset, blobOffset + copyLen), outPtr);\n"
"    }\n"
"    return copyLen;\n"
"  }\n"
"\n"
"  function wardJsBlobFree(handle) {\n"
"    blobCache.delete(handle);\n"
"  }\n"
"\n"
"  // --- Notification/Push ---\n"
"\n"
"  function wardJsNotificationRequestPermission(resolverId) {\n"
"    if (typeof Notification === 'undefined') {\n"
"      instance.exports.ward_on_permission_result(resolverId, 0);\n"
"      return;\n"
"    }\n"
"    Notification.requestPermission().then((perm) => {\n"
"      instance.exports.ward_on_permission_result(resolverId, perm === 'granted' ? 1 : 0);\n"
"    }).catch(() => {\n"
"      instance.exports.ward_on_permission_result(resolverId, 0);\n"
"    });\n"
"  }\n"
"\n"
"  function wardJsNotificationShow(titlePtr, titleLen) {\n"
"    if (typeof Notification === 'undefined') return;\n"
"    const title = readString(titlePtr, titleLen);\n"
"    try { new Notification(title); } catch(e) {}\n"
"  }\n"
"\n"
"  function wardJsPushSubscribe(vapidPtr, vapidLen, resolverId) {\n"
"    try {\n"
"      const vapidBytes = readBytes(vapidPtr, vapidLen);\n"
"      navigator.serviceWorker.ready.then((reg) => {\n"
"        return reg.pushManager.subscribe({\n"
"          userVisibleOnly: true,\n"
"          applicationServerKey: vapidBytes,\n"
"        });\n"
"      }).then((sub) => {\n"
"        const json = JSON.stringify(sub.toJSON());\n"
"        const jsonBytes = new TextEncoder().encode(json);\n"
"        const stashId = stashData(jsonBytes);\n"
"        instance.exports.ward_bridge_stash_set_int(1, stashId);\n"
"        instance.exports.ward_on_push_subscribe(resolverId, jsonBytes.length);\n"
"      }).catch(() => {\n"
"        instance.exports.ward_on_push_subscribe(resolverId, 0);\n"
"      });\n"
"    } catch(e) {\n"
"      instance.exports.ward_on_push_subscribe(resolverId, 0);\n"
"    }\n"
"  }\n"
"\n"
"  function wardJsPushGetSubscription(resolverId) {\n"
"    try {\n"
"      navigator.serviceWorker.ready.then((reg) => {\n"
"        return reg.pushManager.getSubscription();\n"
"      }).then((sub) => {\n"
"        if (!sub) {\n"
"          instance.exports.ward_on_push_subscribe(resolverId, 0);\n"
"          return;\n"
"        }\n"
"        const json = JSON.stringify(sub.toJSON());\n"
"        const jsonBytes = new TextEncoder().encode(json);\n"
"        const stashId = stashData(jsonBytes);\n"
"        instance.exports.ward_bridge_stash_set_int(1, stashId);\n"
"        instance.exports.ward_on_push_subscribe(resolverId, jsonBytes.length);\n"
"      }).catch(() => {\n"
"        instance.exports.ward_on_push_subscribe(resolverId, 0);\n"
"      });\n"
"    } catch(e) {\n"
"      instance.exports.ward_on_push_subscribe(resolverId, 0);\n"
"    }\n"
"  }\n"
"\n"
"  // --- HTML parsing ---\n"
"\n"
"  // Tags filtered out during parsing (security/sanitization)\n"
"  const FILTERED_TAGS = new Set([\n"
"    'script', 'iframe', 'object', 'embed', 'form', 'input', 'link', 'meta'\n"
"  ]);\n"
"\n"
"  function wardJsParseHtml(htmlPtr, htmlLen) {\n"
"    const html = readString(htmlPtr, htmlLen);\n"
"    let doc;\n"
"    try {\n"
"      const win = root.ownerDocument.defaultView;\n"
"      if (typeof win.DOMParser !== 'undefined') {\n"
"        doc = new win.DOMParser().parseFromString(html, 'text/html');\n"
"      } else {\n"
"        return 0;\n"
"      }\n"
"    } catch(e) { return 0; }\n"
"\n"
"    // Serialize DOM tree to binary SAX format\n"
"    const chunks = [];\n"
"    let totalLen = 0;\n"
"\n"
"    function pushByte(b) { chunks.push(new Uint8Array([b])); totalLen += 1; }\n"
"    function pushU16LE(v) { chunks.push(new Uint8Array([v & 0xFF, (v >> 8) & 0xFF])); totalLen += 2; }\n"
"    function pushBytes(arr) { chunks.push(arr); totalLen += arr.length; }\n"
"\n"
"    function serializeNode(node) {\n"
"      if (node.nodeType === 1) { // ELEMENT_NODE\n"
"        const tag = node.tagName.toLowerCase();\n"
"        if (FILTERED_TAGS.has(tag)) return;\n"
"        const tagBytes = new TextEncoder().encode(tag);\n"
"        if (tagBytes.length > 255) return;\n"
"\n"
"        // Collect safe attributes\n"
"        const attrs = [];\n"
"        for (let i = 0; i < node.attributes.length; i++) {\n"
"          const attr = node.attributes[i];\n"
"          if (/^on/i.test(attr.name)) continue;    // skip event handlers\n"
"          if (attr.name === 'style') continue;       // skip style\n"
"          if (!/^[a-zA-Z0-9-]+$/.test(attr.name)) continue; // skip non-safe names\n"
"          const nameBytes = new TextEncoder().encode(attr.name);\n"
"          const valBytes = new TextEncoder().encode(attr.value);\n"
"          if (nameBytes.length > 255 || valBytes.length > 65535) continue;\n"
"          attrs.push({ nameBytes, valBytes });\n"
"        }\n"
"\n"
"        // ELEMENT_OPEN: [0x01] [u8:tag_len] [bytes:tag] [u8:attr_count]\n"
"        pushByte(0x01);\n"
"        pushByte(tagBytes.length);\n"
"        pushBytes(tagBytes);\n"
"        pushByte(attrs.length);\n"
"\n"
"        // per attr: [u8:name_len] [bytes:name] [u16le:value_len] [bytes:value]\n"
"        for (const a of attrs) {\n"
"          pushByte(a.nameBytes.length);\n"
"          pushBytes(a.nameBytes);\n"
"          pushU16LE(a.valBytes.length);\n"
"          pushBytes(a.valBytes);\n"
"        }\n"
"\n"
"        // Recurse children\n"
"        for (let i = 0; i < node.childNodes.length; i++) {\n"
"          serializeNode(node.childNodes[i]);\n"
"        }\n"
"\n"
"        // ELEMENT_CLOSE: [0x02]\n"
"        pushByte(0x02);\n"
"      } else if (node.nodeType === 3) { // TEXT_NODE\n"
"        const text = node.textContent || '';\n"
"        if (text.length === 0) return;\n"
"        const textBytes = new TextEncoder().encode(text);\n"
"        if (textBytes.length > 65535) return;\n"
"        // TEXT: [0x03] [u16le:text_len] [bytes:text]\n"
"        pushByte(0x03);\n"
"        pushU16LE(textBytes.length);\n"
"        pushBytes(textBytes);\n"
"      }\n"
"    }\n"
"\n"
"    // Serialize body children (skip <html>, <head>, <body> wrappers)\n"
"    const body = doc.body;\n"
"    if (body) {\n"
"      for (let i = 0; i < body.childNodes.length; i++) {\n"
"        serializeNode(body.childNodes[i]);\n"
"      }\n"
"    }\n"
"\n"
"    if (totalLen === 0) return 0;\n"
"\n"
"    // Combine chunks and stash for WASM to pull\n"
"    const combined = new Uint8Array(totalLen);\n"
"    let off = 0;\n"
"    for (const chunk of chunks) {\n"
"      combined.set(chunk, off);\n"
"      off += chunk.length;\n"
"    }\n"
"    const stashId = stashData(combined);\n"
"    instance.exports.ward_bridge_stash_set_int(1, stashId);\n"
"    return totalLen;\n"
"  }\n"
"\n"
"  const imports = {\n"
"    env: {\n"
"      ...extraImports,\n"
"      ward_dom_flush: wardDomFlush,\n"
"      ward_js_set_image_src: wardJsSetImageSrc,\n"
"      ward_set_timer: wardSetTimer,\n"
"      ward_exit: () => { resolveDone(); },\n"
"      // IDB\n"
"      ward_idb_js_put: wardIdbPut,\n"
"      ward_idb_js_get: wardIdbGet,\n"
"      ward_idb_js_delete: wardIdbDelete,\n"
"      // Window\n"
"      ward_js_focus_window: wardJsFocusWindow,\n"
"      ward_js_get_visibility_state: wardJsGetVisibilityState,\n"
"      ward_js_log: wardJsLog,\n"
"      // Navigation\n"
"      ward_js_get_url: wardJsGetUrl,\n"
"      ward_js_get_url_hash: wardJsGetUrlHash,\n"
"      ward_js_set_url_hash: wardJsSetUrlHash,\n"
"      ward_js_replace_state: wardJsReplaceState,\n"
"      ward_js_push_state: wardJsPushState,\n"
"      // DOM read\n"
"      ward_js_measure_node: wardJsMeasureNode,\n"
"      ward_js_query_selector: wardJsQuerySelector,\n"
"      // Event listener\n"
"      ward_js_add_event_listener: wardJsAddEventListener,\n"
"      ward_js_remove_event_listener: wardJsRemoveEventListener,\n"
"      ward_js_prevent_default: wardJsPreventDefault,\n"
"      // Fetch\n"
"      ward_js_fetch: wardJsFetch,\n"
"      // Clipboard\n"
"      ward_js_clipboard_write_text: wardJsClipboardWriteText,\n"
"      // File\n"
"      ward_js_file_open: wardJsFileOpen,\n"
"      ward_js_file_read: wardJsFileRead,\n"
"      ward_js_file_close: wardJsFileClose,\n"
"      // Decompress\n"
"      ward_js_decompress: wardJsDecompress,\n"
"      ward_js_blob_read: wardJsBlobRead,\n"
"      ward_js_blob_free: wardJsBlobFree,\n"
"      // Notification/Push\n"
"      ward_js_notification_request_permission: wardJsNotificationRequestPermission,\n"
"      ward_js_notification_show: wardJsNotificationShow,\n"
"      ward_js_push_subscribe: wardJsPushSubscribe,\n"
"      ward_js_push_get_subscription: wardJsPushGetSubscription,\n"
"      // HTML parsing\n"
"      ward_js_parse_html: wardJsParseHtml,\n"
"      // Data stash\n"
"      ward_js_stash_read: wardJsStashRead,\n"
"    },\n"
"  };\n"
"\n"
"  const result = await WebAssembly.instantiate(wasmBytes, imports);\n"
"  instance = result.instance;\n"
"  instance.exports.ward_node_init(0);\n"
"\n"
"  return { exports: instance.exports, nodes, done };\n"
"}\n"
  ;
}
%}
end
