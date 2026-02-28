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

int bats_bridge_measure_get(int slot) {
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
#endif
%}
end
end (* #target wasm *)

(* ============================================================
   produce_bridge -- returns the complete JS bridge as a string
   ============================================================ *)

#pub fun produce_bridge(b: !$B.builder): void

implement produce_bridge(b) = emit_js_all(b)
