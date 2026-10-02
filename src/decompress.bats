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

(* How data is compressed: stored as it is, gzip, zlib's deflate, or
   raw deflate (a zip entry's) *)
#pub datatype compression =
  | Uncompressed
  | Gzip
  | Deflate
  | DeflateRaw

(* What decompressing gave. There is no "nothing" here: data that
   decompresses to no bytes is an empty blob. Linear: Decompressed holds
   a blob JS keeps until it is freed; one no consumer takes is freed by
   promise's dispose. *)
#pub datavtype decompressed =
  | Decompressed of ([n:nat] dblob(n))
  | DecompressFailed  (* damaged data, or no decompressor here *)

(* Decompresses data[0, data_len) *)
#pub fun decompress
  {lb:agz}{n:pos}
  (data: !$A.borrow(byte, lb, n), data_len: int n,
   method: compression): $P.promise(decompressed, $P.Chained)

(* The blob of a handle JS passed (an event's payload, say), or none
   when the handle is not a pending blob: JS's word is checked here,
   once *)
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

(* JS's codes for the methods: 0 stored, 1 gzip, 2 deflate, 8 raw deflate *)
fn _compression_code (method: compression): int =
  case+ method of
  | Uncompressed() => 0
  | Gzip() => 1
  | Deflate() => 2
  | DeflateRaw() => 8

(* JS's codes: a blob's handle (positive), anything else (its 0)
   failed. A handle JS did not hand out is a failure too *)
fn _decompressed (code: Int): decompressed =
  if code <= 0 then DecompressFailed()
  else (case+ blob_claim(code) of
    | ~$R.some(blob) => Decompressed(blob)
    | ~$R.none() => DecompressFailed())

(* A result nobody took: its blob is freed. Before decompress, its first
   use. *)
implement $P.dispose<decompressed>(result) =
  case+ result of
  | ~Decompressed(blob) => blob_free(blob)
  | ~DecompressFailed() => ()

implement decompress{lb}{n}(data, data_len, method) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_decompress(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(data) end,
    data_len, _compression_code(method), id)
in $P.and_then<Int><decompressed>(p, llam (code) =>
  $P.ret<decompressed>(_decompressed(code))) end

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
