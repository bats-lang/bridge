(* file -- file input/read/close for bridge *)

#include "share/atspre_staload.hats"
staload "./stash.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

#pub fun file_open
  : {li:agz}{ni:pos}
  (!$A.borrow(byte, li, ni), int ni) -> $P.promise_pending(int)

#pub fun file_size(): int

#pub fun file_name_len(): int

#pub fun file_name
  : {n:pos | n <= 1048576}
  (int n) -> [l:agz] $A.arr(byte, l, n)

#pub fun file_read
  {l:agz}{n:pos}
  (handle: int, file_offset: int,
   out: !$A.arr(byte, l, n), len: int n): $R.result(int, int)

#pub fun file_close
  (handle: int): void

#pub fun file_store
  {l:agz}{n:pos}
  (!$A.borrow(byte, l, n), int n): int

#pub fun on_file_open
  (resolver_id: int, handle: int, size: int)
  : void = "ext#bats_on_file_open"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_file_open(void*, int, int);
extern int bats_js_file_read(int, int, int, void*);
extern void bats_js_file_close(int);
extern int bats_js_file_store(void*, int);
%}
extern fun _bats_js_file_open
  (id: ptr, id_len: int, resolver_id: int): void = "mac#bats_js_file_open"
extern fun _bats_js_file_read
  (handle: int, file_offset: int, len: int, out: ptr): int = "mac#bats_js_file_read"
extern fun _bats_js_file_close
  (handle: int): void = "mac#bats_js_file_close"
extern fun _bats_js_file_store
  (data: ptr, len: int): int = "mac#bats_js_file_store"
end

implement file_open{li}{ni}(input_node_id, id_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_file_open(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(input_node_id) end, id_len, id)
in p end

implement file_size() = stash_get_int(0)

implement file_name_len() = stash_get_int(2)

implement file_name{n}(len) =
  stash_read(stash_get_int(1), len)

implement file_read{l}{n}(handle, file_offset, out, len) = let
  val r = _bats_js_file_read(handle, file_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement file_close(handle) = _bats_js_file_close(handle)

implement file_store{l}{n}(data, len) =
  _bats_js_file_store(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end, len)

implement on_file_open(resolver_id, handle, size) = let
  val () = stash_set_int(0, size)
in $P.fire(resolver_id, handle) end

end (* #target wasm *)
