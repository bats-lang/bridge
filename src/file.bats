(* file -- file input/read/close for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

#pub fun file_open
  (input_node_id: int): $P.promise(int, $P.Pending)

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

#pub fun on_file_open
  (resolver_id: int, handle: int, size: int)
  : void = "ext#bats_on_file_open"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_js_file_open
  (input_node_id: int, resolver_id: int): void = "mac#bats_js_file_open"
extern fun _bats_js_file_read
  (handle: int, file_offset: int, len: int, out: ptr): int = "mac#bats_js_file_read"
extern fun _bats_js_file_close
  (handle: int): void = "mac#bats_js_file_close"

implement file_open(input_node_id) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_file_open(input_node_id, id)
in p end

implement file_size() = stash_get_int(0)

implement file_name_len() = stash_get_int(2)

implement file_name{n}(len) =
  stash_read(stash_get_int(1), len)

implement file_read{l}{n}(handle, file_offset, out, len) = let
  val r = _bats_js_file_read(handle, file_offset, len,
    $UNSAFE.castvwtp1{ptr}(out))
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement file_close(handle) = _bats_js_file_close(handle)

implement on_file_open(resolver_id, handle, size) = let
  val () = stash_set_int(0, size)
in $P.fire(resolver_id, handle) end

end (* $UNSAFE *)
end (* #target wasm *)
