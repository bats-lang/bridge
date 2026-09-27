(* decompress -- decompression with blob cache for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* A decompressed blob of n bytes, held by JS until freed. Claimed once
   from the handle its promise resolves with; its reads are in range by
   type, so they cannot fail. *)
#pub absvtype dblob(n:int) = ptr

#pub fun decompress_req
  {lb:agz}{n:pos}
  (data: !$A.borrow(byte, lb, n), data_len: int n,
   method: int, resolver_id: int): void

(* The blob a decompress promise resolved with, or none when it failed
   (handle 0) or the handle is not a pending blob: JS's word is checked
   here, once *)
#pub fun blob_claim
  (handle: Int): $R.option([n:nat] dblob(n))

#pub fun blob_len {n:nat} (b: !dblob(n)): int n

(* out[0, len) := the blob's bytes [blob_offset, blob_offset + len) *)
#pub fun blob_read
  {n:nat}{o,k:nat | o + k <= n}{l:agz}{ow:addr}{m:pos | k <= m}
  (b: !dblob(n), blob_offset: int o,
   out: !$A.arrx(byte, l, m, ow), len: int k): void

#pub fun blob_free {n:nat} (b: dblob(n)): void

#pub fun on_decompress_complete
  (resolver_id: int, handle: Int)
  : void = "ext#bats_on_decompress_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_decompress(void*, int, int, int);
extern int bats_js_blob_claim(int);
extern void bats_js_blob_read(int, int, int, void*);
extern void bats_js_blob_free(int);
%}
extern fun _bats_js_decompress
  (data: ptr, data_len: int, method: int, resolver_id: int)
  : void = "mac#bats_js_decompress"
extern fun _bats_js_blob_claim
  (handle: int): [v:int] int v = "mac#bats_js_blob_claim"
extern fun _bats_js_blob_read
  (handle: int, blob_offset: int, len: int, out: ptr): void = "mac#bats_js_blob_read"
extern fun _bats_js_blob_free
  (handle: int): void = "mac#bats_js_blob_free"

datavtype blob_rep(int) = {n:nat} BlobRep(n) of (int, int n)
assume dblob(n) = blob_rep(n)
end

implement decompress_req{lb}{n}(data, data_len, method, resolver_id) =
  _bats_js_decompress(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end,
    data_len, method, resolver_id)

implement blob_claim(handle) = let
  val n = _bats_js_blob_claim(handle)
in
  if n >= 0 then $R.some(BlobRep(handle, n)) else $R.none()
end

implement blob_len{n}(b) = let
  val+ BlobRep(_, n) = b
in n end

implement blob_read{n}{o,k}{l}{ow}{m}(b, blob_offset, out, len) = let
  val+ BlobRep(h, _) = b
in
  _bats_js_blob_read(h, blob_offset, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(out) end)
end

implement blob_free{n}(b) = let
  val+ ~BlobRep(h, _) = b
in _bats_js_blob_free(h) end

implement on_decompress_complete(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
