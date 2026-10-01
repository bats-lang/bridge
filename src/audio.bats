(* audio -- playing a media element (an <audio> or <video>) for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* Plays the media element with that id from where it is; the promise
   resolves with 0 once it plays, 1 when the browser refused it (no
   user activation, NotAllowedError), 2 when it cannot be played or
   there is no such element *)
#pub fun audio_play
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): $P.promise_pending(Int)

(* Pauses the media element with that id (nothing when there is none) *)
#pub fun audio_pause
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): void

(* Moves its playback position to ms milliseconds *)
#pub fun audio_seek
  {li:agz}{ni:pos}{ms:nat}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni, ms: int ms): void

(* playbackRate := hundredths / 100, with preservesPitch true *)
#pub fun audio_rate
  {li:agz}{ni:pos}{hundredths:int | 25 <= hundredths; hundredths <= 400}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni,
   hundredths: int hundredths): void

(* Its playback position in whole ms, or -1 when there is no such
   element *)
#pub fun audio_time
  {li:agz}{ni:pos}
  (node_id: !$A.borrow(byte, li, ni), id_len: int ni): [v:int] int v

#pub fun on_audio_play
  (resolver_id: int, result: Int): void = "ext#bats_on_audio_play"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_audio_play(void*, int, int);
extern void bats_js_audio_pause(void*, int);
extern void bats_js_audio_seek(void*, int, int);
extern void bats_js_audio_rate(void*, int, int);
extern int bats_js_audio_time(void*, int);
%}
extern fun _bats_js_audio_play
  (id: ptr, id_len: int, resolver_id: int): void = "mac#bats_js_audio_play"
extern fun _bats_js_audio_pause
  (id: ptr, id_len: int): void = "mac#bats_js_audio_pause"
extern fun _bats_js_audio_seek
  (id: ptr, id_len: int, ms: int): void = "mac#bats_js_audio_seek"
extern fun _bats_js_audio_rate
  (id: ptr, id_len: int, hundredths: int): void = "mac#bats_js_audio_rate"
extern fun _bats_js_audio_time
  (id: ptr, id_len: int): [v:int] int v = "mac#bats_js_audio_time"
end

implement audio_play{li}{ni}(node_id, id_len) = let
  val @(p, r) = $P.create<Int>()
  val resolver_id = $P.stash(r)
  val () = _bats_js_audio_play(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, resolver_id)
in p end

implement audio_pause{li}{ni}(node_id, id_len) =
  _bats_js_audio_pause(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len)

implement audio_seek{li}{ni}{ms}(node_id, id_len, ms) =
  _bats_js_audio_seek(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, ms)

implement audio_rate{li}{ni}{hundredths}(node_id, id_len, hundredths) =
  _bats_js_audio_rate(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len, hundredths)

implement audio_time{li}{ni}(node_id, id_len) =
  _bats_js_audio_time(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(node_id) end, id_len)

implement on_audio_play(resolver_id, result) =
  $P.fire(resolver_id, result)

end (* #target wasm *)
