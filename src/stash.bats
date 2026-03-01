(* stash -- data stash read/write for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun stash_read
  {n:pos | n <= 1048576}
  (stash_id: int, len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun stash_set_int
  (slot: int, v: int): void

#pub fun stash_get_int
  (slot: int): int

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_js_stash_read
  (stash_id: int, dest: ptr, len: int): void = "mac#bats_js_stash_read"

fun _bridge_recv{n:pos | n <= 1048576}
  (stash_id: int, len: int n): [l:agz] $A.arr(byte, l, n) = let
  val buf = $A.alloc<byte>(len)
  val p = $UNSAFE.castvwtp1{ptr}(buf)
  val () = _bats_js_stash_read(stash_id, p, len)
in buf end

fn _stash_get_int(slot: int): int =
  $extfcall(int, "bats_bridge_stash_get_int", slot)

fn _stash_set_int(slot: int, v: int): void =
  $extfcall(void, "bats_bridge_stash_set_int", slot, v)

implement stash_read{n}(stash_id, len) =
  _bridge_recv(stash_id, len)

implement stash_set_int(slot, v0) = _stash_set_int(slot, v0)

implement stash_get_int(slot) = _stash_get_int(slot)

end (* $UNSAFE *)
end (* #target wasm *)
