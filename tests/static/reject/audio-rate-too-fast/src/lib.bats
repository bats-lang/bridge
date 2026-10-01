#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload AU = "wasm.bats-packages.dev/bridge/src/audio.sats"

(* Five times as fast is past the rate's bound of 4 (400 hundredths) *)
fn f (): void = let
  val node_id = $A.alloc<byte>(5)
  val () = $A.write_text(node_id, 0, $A.text_lit("audio"), 5)
  val @(frozen, borrowed) = $A.freeze<byte>(node_id)
  val () = $AU.audio_rate(borrowed, 5, 500)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
