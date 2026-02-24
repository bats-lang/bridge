(* bridge -- centralized WASM host import wrappers for bats *)
(* No other package touches $UNSAFE or declares extern WASM imports. *)
(* Bridge exports safe #pub fun wrappers over all mac# host calls. *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   C runtime -- stash, measure, listener tables + WASM exports
   ============================================================ *)

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

#pub fun produce_bridge(): string
