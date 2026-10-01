#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload SP = "wasm.bats-packages.dev/bridge/src/speech.sats"

(* A fifth of the normal speed (20 hundredths) is below the rate's
   bound of 25 *)
fn f (): int = let
  val text = $A.alloc<byte>(2)
  val () = $A.write_text(text, 0, $A.text_lit("Hi"), 2)
  val @(frozen, borrowed) = $A.freeze<byte>(text)
  val lang = $A.dup<byte>(frozen, borrowed)
  val voice = $A.dup<byte>(frozen, borrowed)
  val utterance = $SP.speech_speak(borrowed, 2, lang, 0, voice, 0, 20)
  val () = $A.drop<byte>(frozen, voice)
  val () = $A.drop<byte>(frozen, lang)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in utterance end
