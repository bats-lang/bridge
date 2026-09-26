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
  {s:nat | s < 32}
  (slot: int s, v: int): void

(* The int JS stashed in slot. It can be any int, so it is returned
   indexed: a caller can then check it and use it as a size or index
   with no cast. *)
#pub fun stash_get_int
  {s:nat | s < 32}
  (slot: int s): [v:int] int v

(* Get root element's HTML id as stashed string. Returns byte length.
   Read the string with stash_read(stash_get_int(1), len). *)
#pub fun get_root_node(): int

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
%}
extern fun _bats_js_stash_read
  (stash_id: int, dest: ptr, len: int): void = "mac#bats_js_stash_read"
extern fun _bats_js_get_root_node
  (): int = "mac#bats_js_get_root_node"
end

fn _bridge_recv{n:pos | n <= 1048576}
  (stash_id: int, len: int n): [l:agz] $A.arr(byte, l, n) = let
  val buf = $A.alloc<byte>(len)
  val p = $UNSAFE begin $UNSAFE.castvwtp1{ptr}(buf) end
  val () = _bats_js_stash_read(stash_id, p, len)
in buf end

fn _stash_get_int{s:nat | s < 32}(slot: int s): [v:int] int v =
  $UNSAFE begin $extfcall([v:int] int v, "bats_bridge_stash_get_int", slot) end

fn _stash_set_int{s:nat | s < 32}(slot: int s, v: int): void =
  $UNSAFE begin $extfcall(void, "bats_bridge_stash_set_int", slot, v) end

implement stash_read{n}(stash_id, len) =
  _bridge_recv(stash_id, len)

implement stash_set_int{s}(slot, v0) = _stash_set_int(slot, v0)

implement stash_get_int{s}(slot) = _stash_get_int(slot)

implement get_root_node() = _bats_js_get_root_node()

end (* #target wasm *)
