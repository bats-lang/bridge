(* decompress -- decompression with blob cache for bridge *)

#include "share/atspre_staload.hats"
staload "./stash.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

#pub fun decompress_req
  {lb:agz}{n:pos}
  (data: !$A.borrow(byte, lb, n), data_len: int n,
   method: int, resolver_id: int): void

#pub fun decompress_len(): [n:int] int n

#pub fun blob_read
  {l:agz}{n:pos}
  (handle: int, blob_offset: int,
   out: !$A.arr(byte, l, n), len: int n): $R.result(int, int)

#pub fun blob_free
  (handle: int): void

#pub fun on_decompress_complete
  (resolver_id: int, handle: int, decompressed_len: int)
  : void = "ext#bats_on_decompress_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_decompress(void*, int, int, int);
extern int bats_js_blob_read(int, int, int, void*);
extern void bats_js_blob_free(int);
%}
extern fun _bats_js_decompress
  (data: ptr, data_len: int, method: int, resolver_id: int)
  : void = "mac#bats_js_decompress"
extern fun _bats_js_blob_read
  (handle: int, blob_offset: int, len: int, out: ptr): int = "mac#bats_js_blob_read"
extern fun _bats_js_blob_free
  (handle: int): void = "mac#bats_js_blob_free"
end

implement decompress_req{lb}{n}(data, data_len, method, resolver_id) =
  _bats_js_decompress(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end,
    data_len, method, resolver_id)

implement decompress_len() = stash_get_int(0)

implement blob_read{l}{n}(handle, blob_offset, out, len) = let
  val r = _bats_js_blob_read(handle, blob_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
in
  if r >= 0 then $R.ok(r) else $R.err(r)
end

implement blob_free(handle) = _bats_js_blob_free(handle)

implement on_decompress_complete(resolver_id, handle, decompressed_len) = let
  val () = stash_set_int(0, decompressed_len)
in $P.fire(resolver_id, handle) end

end (* #target wasm *)
