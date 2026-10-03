(* media -- media query matching and listening for bridge *)

#include "share/atspre_staload.hats"
staload "./event.bats"

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

(* Where the page's fonts stand as a load of some of them ends, as
   listen_fonts_loaded passes it (document.fonts.status, read as the
   event comes): FontsSettled when none is loading any more,
   FontsStillLoading when others are *)
#pub datatype fonts_status =
  | FontsSettled
  | FontsStillLoading

(* A listener for the page's fonts: called each time fonts the page
   asked for have finished loading (document.fonts' loadingdone). Text
   laid out before a face arrived was measured with a fallback, so what
   was measured then (a page count, a position) can be measured again
   here. Where the browser has no document.fonts, it is never called. *)
#pub fun listen_fonts_loaded
  (listener_id: listener_id,
   callback: (fonts_status) -<lincloptr1> void): void

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
extern void bats_listener_set_decoded(int id, void *decoder, void *inner);
extern int bats_js_fonts_loading(void);
extern void bats_js_listen_fonts(int);
%}
extern fun _bats_js_match_media
  (query: ptr, query_len: int): int = "mac#bats_js_match_media"
extern fun _bats_js_listen_media
  (query: ptr, query_len: int, listener_id: int)
  : void = "mac#bats_js_listen_media"
extern fun _bats_js_fonts_loading
  (): int = "mac#bats_js_fonts_loading"
extern fun _bats_js_listen_fonts
  (listener_id: int): void = "mac#bats_js_listen_fonts"
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

(* The event carries no payload: the fonts' status is read as it comes,
   so there is nothing to decode that could be wrong. The slot holds the
   decoder and the callback, and frees both (the decoder holds only the
   callback's pointer). JS's codes: 1 still loading, else settled. *)
implement listen_fonts_loaded(listener_id, callback) = let
  val inner = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(callback) end
  val decode = llam (payload: event_payload): int =<lincloptr1> let
    val call = $UNSAFE begin $UNSAFE.cast{(fonts_status) -<cloref1> void}(inner) end
    val () = call(if _bats_js_fonts_loading() = 1
      then FontsStillLoading() else FontsSettled())
  in 0 end
  val decoder = $UNSAFE begin $UNSAFE.castvwtp0{ptr}(decode) end
  val () = $UNSAFE begin
    $extfcall(void, "bats_listener_set_decoded", listener_id, decoder, inner) end
in _bats_js_listen_fonts(listener_id) end

end (* #target wasm *)
