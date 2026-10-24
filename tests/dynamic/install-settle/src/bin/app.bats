#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"
staload AP = "wasm.bats-packages.dev/bridge/src/app.bats"

(* Shows the browser's offer to install with each form and says how each
   ended in the address's hash, as a line: check.mjs plays the offer and
   prints each hash. The answer of install_prompt_answer is matched with
   case+, every constructor visible. The old install_prompt is called too
   (it is kept for one version, bridge#229), so an edit cannot drop it: it
   says accepted, dismissed or unavailable, and a rejection is unavailable,
   as it always was (bridge#186). The offer is used up by the first call,
   so the old one is called when check.mjs makes the next offer, which the
   listener of the offer's coming passes. *)

fn say {l:agz}{n:pos | n <= 4096} (a: $A.arr(byte, l, n), n: int n): void = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn say_text {n:pos | n < 256} (s: string n): void = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in say(a, n) end

(* The text a call rejected with, as the next hash after the outcome's name *)
fn say_blob {n:nat} (blob: !$BD.dblob(n)): void = let
  val n = $BD.blob_len(blob)
in
  if n <= 0 then say_text("no text")
  else if n > 4096 then say_text("long text")
  else let
    val a = $A.alloc<byte>(n)
    val () = $BD.blob_read(blob, 0, a, n)
  in say(a, n) end
end

fn say_answer (answer: $AP.install_answer): void =
  case+ answer of
  | ~$AP.InstallAnswerAccepted() => say_text("accepted")
  | ~$AP.InstallAnswerDismissed() => say_text("dismissed")
  | ~$AP.InstallAnswerNoOffer() => say_text("no offer")
  | ~$AP.InstallAnswerRejected(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("rejected") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("rejected: no text"))
  | ~$AP.InstallAnswerThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$AP.InstallAnswerOdd(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("odd") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("odd: no text"))
  | ~$AP.InstallAnswerUnexpected(_) => say_text("unexpected")

fn say_old (old: $AP.install_outcome): void =
  case+ old of
  | $AP.InstallAccepted() => say_text("old: accepted")
  | $AP.InstallDismissed() => say_text("old: dismissed")
  | $AP.InstallUnavailable() => say_text("old: unavailable")

implement main0 () = let
  val () = $AP.listen_install_prompt(2, llam (offer) =>
    case+ offer of
    | $AP.InstallOffered() =>
      $P.finish<$AP.install_outcome>($AP.install_prompt(), llam (old) => say_old(old))
    | $AP.InstallWithdrawn() => ())
in
  $P.finish<$AP.install_answer>($AP.install_prompt_answer(), llam (answer) =>
    say_answer(answer))
end
