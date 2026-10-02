#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload AU = "wasm.bats-packages.dev/bridge/src/audio.sats"

(* A play matched without Unplayable *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$AU.play_outcome>($AU.audio_play(borrowed, 3), llam (outcome) =>
    case+ outcome of
    | $AU.Playing() => ()
    | $AU.PlayRefused() => ())
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
