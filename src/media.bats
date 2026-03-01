(* media -- media query matching and listening for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

#pub fun match_media
  {lb:agz}{n:pos}
  (query: !$A.borrow(byte, lb, n), query_len: int n): int

#pub fun listen_media
  {lb:agz}{n:pos}
  (query: !$A.borrow(byte, lb, n), query_len: int n,
   listener_id: int, callback: (int) -<cloref1> int): void

#pub fun on_media_change
  (listener_id: int, matches: int): void = "ext#bats_on_media_change"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin

extern fun _bats_js_match_media
  (query: ptr, query_len: int): int = "mac#bats_js_match_media"
extern fun _bats_js_listen_media
  (query: ptr, query_len: int, listener_id: int)
  : void = "mac#bats_js_listen_media"

implement match_media{lb}{n}(query, query_len) =
  _bats_js_match_media(
    $UNSAFE.castvwtp1{ptr}(query), query_len)

implement listen_media{lb}{n}(query, query_len, listener_id, callback) = let
  val cbp = $UNSAFE.castvwtp0{ptr}(callback)
  val () = $extfcall(void, "bats_listener_set", listener_id, cbp)
in _bats_js_listen_media(
    $UNSAFE.castvwtp1{ptr}(query), query_len,
    listener_id) end

implement on_media_change(listener_id, matches) = let
  val cbp = $extfcall(ptr, "bats_listener_get", listener_id)
in
  if ptr_isnot_null(cbp) then let
    val cb = $UNSAFE.cast{(int) -<cloref1> int}(cbp)
    val _ = cb(matches)
  in () end
  else ()
end

end (* $UNSAFE *)
end (* #target wasm *)
