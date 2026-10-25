#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Shares the text "Hi" with the title "T" with share_text_answer and then,
   again, with the old share_text, and says how each ended in the address's
   hash, as a line: check.mjs prints each hash. The answer of
   share_text_answer is matched with case+, every constructor visible, and
   the old share_text is called too (it is kept for one version,
   bridge#241), so an edit cannot drop it: it says only shared, cancelled or
   failed, as it always did (bridge#186). *)

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$SH.share_outcome>(_) = ()
implement $P.dispose<$SH.text_share_answer>(answer) =
  case+ answer of
  | ~$SH.TextAnswerShared() => ()
  | ~$SH.TextAnswerCancelled() => ()
  | ~$SH.TextAnswerFailed(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$SH.TextAnswerNotHere() => ()
  | ~$SH.TextAnswerRejected(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$SH.TextAnswerThrown(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$SH.TextAnswerUnexpected(_) => ()

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

(* A blob's bytes, as the next hash *)
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

fn say_answer (answer: $SH.text_share_answer): void =
  case+ answer of
  | ~$SH.TextAnswerShared() => say_text("shared")
  | ~$SH.TextAnswerCancelled() => say_text("cancelled")
  | ~$SH.TextAnswerFailed(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("failed") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("failed: no text"))
  | ~$SH.TextAnswerNotHere() => say_text("not here")
  | ~$SH.TextAnswerRejected(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("rejected") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("rejected: no text"))
  | ~$SH.TextAnswerThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$SH.TextAnswerUnexpected(_) => say_text("unexpected")

fn say_old (old: $SH.share_outcome): void =
  case+ old of
  | $SH.Shared() => say_text("old: shared")
  | $SH.Cancelled() => say_text("old: cancelled")
  | $SH.ShareFailed() => say_text("old: failed")

(* "T" and "Hi" in fresh arrays *)
fn title_bytes (): [l:agz] $A.arr(byte, l, 1) = let
  val a = $A.alloc<byte>(1)
  val () = $A.write_text(a, 0, $A.text_lit("T"), 1)
in a end

fn text_bytes (): [l:agz] $A.arr(byte, l, 2) = let
  val a = $A.alloc<byte>(2)
  val () = $A.write_text(a, 0, $A.text_lit("Hi"), 2)
in a end

(* Shares "Hi" titled "T" with the new form *)
fn share_answer (): $P.promise($SH.text_share_answer, $P.Chained) = let
  val @(title_frozen, title_borrowed) = $A.freeze<byte>(title_bytes())
  val @(text_frozen, text_borrowed) = $A.freeze<byte>(text_bytes())
  val answered = $SH.share_text_answer(title_borrowed, 1, text_borrowed, 2)
  val () = $A.drop<byte>(text_frozen, text_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(text_frozen))
  val () = $A.drop<byte>(title_frozen, title_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(title_frozen))
in answered end

(* The same with the old form *)
fn share_old (): $P.promise($SH.share_outcome, $P.Chained) = let
  val @(title_frozen, title_borrowed) = $A.freeze<byte>(title_bytes())
  val @(text_frozen, text_borrowed) = $A.freeze<byte>(text_bytes())
  val outcome = $SH.share_text(title_borrowed, 1, text_borrowed, 2)
  val () = $A.drop<byte>(text_frozen, text_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(text_frozen))
  val () = $A.drop<byte>(title_frozen, title_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(title_frozen))
in outcome end

implement main0 () =
  $P.finish<$SH.text_share_answer>(share_answer(), llam (answer) => let
    val () = say_answer(answer)
  in
    $P.finish<$SH.share_outcome>(share_old(), llam (old) => say_old(old))
  end)
