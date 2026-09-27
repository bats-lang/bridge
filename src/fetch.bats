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
%}
extern fun _bats_js_fetch
  (url: ptr, url_len: int, resolver_id: int): void = "mac#bats_js_fetch"
extern fun _bats_js_fetch_status
  (handle: int): [s:int] int s = "mac#bats_js_fetch_status"
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

implement on_fetch_complete(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
