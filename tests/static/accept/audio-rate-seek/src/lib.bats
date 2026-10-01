#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload AU = "wasm.bats-packages.dev/bridge/src/audio.sats"

(* One and a half times as fast, from 2.5 s in: a rate inside
   [0.25, 4] and a position that is not negative *)
fn f (): void = let
  val node_id = $A.alloc<byte>(5)
  val () = $A.write_text(node_id, 0, $A.text_lit("audio"), 5)
  val @(frozen, borrowed) = $A.freeze<byte>(node_id)
  val () = $AU.audio_rate(borrowed, 5, 150)
  val () = $AU.audio_seek(borrowed, 5, 2500)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
