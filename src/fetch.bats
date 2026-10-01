(* fetch -- network fetch with promise-based async for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Fetches the URL; the promise resolves with a handle to the response,
   0 when the request failed, to claim with fetch_claim *)
#pub fun fetch
  : {lb:agz}{n:pos}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise_pending(Int)

(* The response a fetch promise resolved with: its HTTP status and its
   body, a blob of its own size; none when the request failed or the
   handle is not a pending response. Claimed once. *)
#pub fun fetch_claim
  (handle: Int): $R.option(@([s:int] int s, [k:nat] dblob(k)))

(* Sends a request: its method (GET, PUT and the like), the URL, the
   value of its Authorization header and of its If-Match header (each
   left out when it is empty) and its body (none when it is empty).
   The promise resolves as fetch's does, with a handle to claim with
   fetch_claim or fetch_claim_tagged *)
#pub fun fetch_send
  : {method_loc:agz}{method_len:pos}{url_loc:agz}{url_len:pos}
    {authorization_loc:agz}{authorization_size:nat}{authorization_len:nat | authorization_len <= authorization_size}
    {match_loc:agz}{match_size:nat}{match_len:nat | match_len <= match_size}
    {body_loc:agz}{body_size:nat}{body_len:nat | body_len <= body_size}
  (!$A.borrow(byte, method_loc, method_len), int method_len,
   !$A.borrow(byte, url_loc, url_len), int url_len,
   !$A.borrow(byte, authorization_loc, authorization_size), int authorization_len,
   !$A.borrow(byte, match_loc, match_size), int match_len,
   !$A.borrow(byte, body_loc, body_size), int body_len) -> $P.promise_pending(Int)

(* As fetch_claim, with the response's ETag header written to etag:
   its length, at most etag_size, and 0 when the response has none, it
   is longer, or the server does not let the page read it *)
#pub fun fetch_claim_tagged
  {etag_loc:agz}{etag_size:pos}
  (handle: Int, etag: !$A.arr(byte, etag_loc, etag_size), etag_size: int etag_size)
  : $R.option(@([s:int] int s, [k:nat | k <= etag_size] int k, [k:nat] dblob(k)))

#pub fun on_fetch_complete
  (resolver_id: int, handle: Int)
  : void = "ext#bats_on_fetch_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_fetch(void*, int, int);
extern int bats_js_fetch_status(int);
extern void bats_js_fetch_send(void*, int, void*, int, void*, int, void*, int, void*, int, int);
extern int bats_js_fetch_etag(int, void*, int);
%}
extern fun _bats_js_fetch
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_fetch"
extern fun _bats_js_fetch_status
  (handle: int): [s:int] int s = "mac#bats_js_fetch_status"
extern fun _bats_js_fetch_send
  (method: ptr, method_len: int, url: ptr, url_len: int,
   authorization: ptr, authorization_len: int, match: ptr, match_len: int,
   body: ptr, body_len: int, resolver_id: int): void = "mac#bats_js_fetch_send"
extern fun _bats_js_fetch_etag
  (handle: int, etag: ptr, etag_size: int): int = "mac#bats_js_fetch_etag"
end

implement fetch{lb}{n}(url, url_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_fetch(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    id)
in p end

implement fetch_claim(handle) = let
  (* The status is taken first: JS drops it when the body is claimed *)
  val status = _bats_js_fetch_status(handle)
in
  case+ blob_claim(handle) of
  | ~$R.none() => $R.none()
  | ~$R.some(b) => $R.some(@(status, b))
end

implement fetch_send{method_loc}{method_len}{url_loc}{url_len}
  {authorization_loc}{authorization_size}{authorization_len}
  {match_loc}{match_size}{match_len}{body_loc}{body_size}{body_len}
  (method, method_len, url, url_len, authorization, authorization_len,
   match, match_len, body, body_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_fetch_send(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(method) end, method_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(url) end, url_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(authorization) end, authorization_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(match) end, match_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(body) end, body_len,
    id)
in p end

implement fetch_claim_tagged{etag_loc}{etag_size}(handle, etag, etag_size) = let
  (* The ETag and the status are taken first: JS drops them when the
     body is claimed *)
  val etag_written = _bats_js_fetch_etag(handle,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(etag) end, etag_size)
  val etag_len = g1ofg0(etag_written)
  val status = _bats_js_fetch_status(handle)
in
  case+ blob_claim(handle) of
  | ~$R.none() => $R.none()
  | ~$R.some(b) =>
    if etag_len < 0 then $R.some(@(status, 0, b))
    else if etag_len > etag_size then $R.some(@(status, 0, b))
    else $R.some(@(status, etag_len, b))
end

implement on_fetch_complete(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
