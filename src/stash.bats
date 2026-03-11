(* stash -- data stash read/write for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun stash_read
  : {n:pos | n <= 1048576}
  (int, int n) -> [l:agz] $A.arr(byte, l, n)

#pub fun stash_set_int
  (slot: int, v: int): void

#pub fun stash_get_int
  (slot: int): int

(* Get root element's HTML id as stashed string. Returns byte length.
   Read the string with stash_read(stash_get_int(1), len). *)
#pub fun get_root_node(): int

(* Linear resource stash: store/retrieve viewtype values by slot.
   Consumes the value on stash, produces it on unstash.
   The caller must unstash with the same type that was stashed. *)
#pub fun{a:vt@ype}
stash_linear
  (slot: int, x: a): void

#pub fun{a:vt@ype}
unstash_linear
  (slot: int): a

(* Convert bytes from a borrow to a persistent string.
   Copies len bytes starting at off. The result is null-terminated. *)
#pub fun borrow_to_string
  {l:agz}{n:pos}
  (bv: !$A.borrow(byte, l, n), off: int, len: int, max: int n): string

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern int bats_bridge_stash_get_int(int slot);
extern void bats_bridge_stash_set_int(int slot, int v);
extern void bats_js_stash_read(int, void*, int);
extern int bats_js_get_root_node(void);

#ifndef _BATS_BYTES_TO_STRING_DEFINED
#define _BATS_BYTES_TO_STRING_DEFINED
#include <stdlib.h>
#include <string.h>
static char* _bats_borrow_to_string(void* base, int off, int len, int max) {
  char* s;
  if (off < 0 || len <= 0 || off + len > max) { s = (char*)malloc(1); s[0] = '\0'; return s; }
  s = (char*)malloc(len + 1);
  memcpy(s, (char*)base + off, len);
  s[len] = '\0';
  return s;
}
#endif

#ifndef _BATS_STASH_PTR_DEFINED
#define _BATS_STASH_PTR_DEFINED
#define _BATS_STASH_PTR_SLOTS 8
static void* _bats_stash_ptrs[_BATS_STASH_PTR_SLOTS];
static void _bats_stash_set_ptr(int slot, void* p) {
  if (slot >= 0 && slot < _BATS_STASH_PTR_SLOTS) _bats_stash_ptrs[slot] = p;
}
static void* _bats_stash_get_ptr(int slot) {
  return (slot >= 0 && slot < _BATS_STASH_PTR_SLOTS) ? _bats_stash_ptrs[slot] : (void*)0;
}
#endif
%}
extern fun _bats_js_stash_read
  (stash_id: int, dest: ptr, len: int): void = "mac#bats_js_stash_read"
extern fun _bats_js_get_root_node
  (): int = "mac#bats_js_get_root_node"
extern fun _bats_stash_set_ptr
  (slot: int, p: ptr): void = "mac#_bats_stash_set_ptr"
extern fun _bats_stash_get_ptr
  (slot: int): ptr = "mac#_bats_stash_get_ptr"
extern fun _bats_borrow_to_string
  (base: ptr, off: int, len: int, max: int): string = "mac#_bats_borrow_to_string"
end

fun _bridge_recv{n:pos | n <= 1048576}
  (stash_id: int, len: int n): [l:agz] $A.arr(byte, l, n) = let
  val buf = $A.alloc<byte>(len)
  val p = $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buf) end
  val () = _bats_js_stash_read(stash_id, p, len)
in buf end

fn _stash_get_int(slot: int): int =
  $UNSAFE begin $extfcall(int, "bats_bridge_stash_get_int", slot) end

fn _stash_set_int(slot: int, v: int): void =
  $UNSAFE begin $extfcall(void, "bats_bridge_stash_set_int", slot, v) end

implement stash_read{n}(stash_id, len) =
  _bridge_recv(stash_id, len)

implement stash_set_int(slot, v0) = _stash_set_int(slot, v0)

implement stash_get_int(slot) = _stash_get_int(slot)

implement get_root_node() = _bats_js_get_root_node()

implement{a}
stash_linear(slot, x) = let
  val p = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(x) end
in _bats_stash_set_ptr(slot, p) end

implement{a}
unstash_linear(slot) = let
  val p = _bats_stash_get_ptr(slot)
in $UNSAFE begin $UNSAFE.castvwtp0{a}(p) end end

implement borrow_to_string{l}{n}(bv, off, len, max) = let
  val p = $UNSAFE begin $UNSAFE.castvwtp1{ptr}(bv) end
in _bats_borrow_to_string(p, off, len, max) end

end (* #target wasm *)
