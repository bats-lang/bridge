(* media -- media query matching and listening for bridge *)

#include "share/atspre_staload.hats"

#use array as A

(* ============================================================
   Public API
   ============================================================ *)

(* Whether a media query matches. JS's answer is decoded here, once:
   anything but its 1 is NoMatch. *)
#pub datatype media_match =
  | Matches
  | NoMatch

#pub fun match_media
  {lb:agz}{n:pos}
  (query: !$A.borrow(byte, lb, n), query_len: int n): media_match

(* The callback gets whether the query matches now, each time that
   changes. It is a linear closure (llam), kept in the listener's slot
   and freed with it (unlisten), as event.bats's listeners are. *)
#pub fun listen_media
  {lb:agz}{n:pos}
  (query: !$A.borrow(byte, lb, n), query_len: int n,
   listener_id: [i:nat | i < 128] int i, callback: (media_match) -<lincloptr1> int): void

#pub fun on_media_change
  (listener_id: int, matches: Int): void = "ext#bats_on_media_change"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_listener_set(int id, void *cb);
extern void *bats_listener_get(int id);
extern void bats_listener_enter(void);
extern void bats_listener_leave(void);
extern int bats_js_match_media(void*, int);
extern void bats_js_listen_media(void*, int, int);
%}
extern fun _bats_js_match_media
  (query: ptr, query_len: int): int = "mac#bats_js_match_media"
extern fun _bats_js_listen_media
  (query: ptr, query_len: int, listener_id: int)
  : void = "mac#bats_js_listen_media"
end

(* JS's codes: 1 matches, 0 not *)
fn _media_match (code: int): media_match =
  if code = 1 then Matches() else NoMatch()

implement match_media{lb}{n}(query, query_len) =
  _media_match(_bats_js_match_media(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(query) end, query_len))

implement listen_media{lb}{n}(query, query_len, listener_id, callback) = let
  val cbp = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val () = $UNSAFE begin $extfcall(void, "bats_listener_set", listener_id, cbp) end
in _bats_js_listen_media(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(query) end, query_len,
    listener_id) end

implement on_media_change(listener_id, matches) = let
  val cbp = $UNSAFE begin $extfcall(ptr, "bats_listener_get", listener_id) end
in
  if ptr_isnot_null(cbp) then let
    val () = $UNSAFE begin $extfcall(void, "bats_listener_enter") end
    val cb = $UNSAFE begin $UNSAFE.cast{(media_match) -<cloref1> int}(cbp) end
    val _ = cb(_media_match(matches))
  in $UNSAFE begin $extfcall(void, "bats_listener_leave") end end
  else ()
end

end (* #target wasm *)
