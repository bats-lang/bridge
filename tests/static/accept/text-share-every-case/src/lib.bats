#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"

(* A text share matched in every case, its text freed; the old form matched too
   (kept for one version, bridge#241); an answer let go is freed by its
   dispose *)
fn f {lt:agz}{nt:pos}{kt:nat | kt <= nt}{lx:agz}{nx:pos}
  (title: !$A.borrow(byte, lt, nt), title_len: int kt,
   text_bytes: !$A.borrow(byte, lx, nx), text_len: int nx): void = let
  val () = $P.finish<$SH.text_share_answer>($SH.share_text_answer(title, title_len, text_bytes, text_len), llam (answer) =>
    case+ answer of
    | ~$SH.TextAnswerShared() => ()
    | ~$SH.TextAnswerCancelled() => ()
    | ~$SH.TextAnswerFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.TextAnswerNotHere() => ()
    | ~$SH.TextAnswerRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.TextAnswerThrown(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.TextAnswerUnexpected(_) => ())
  val () = $P.finish<$SH.share_outcome>($SH.share_text(title, title_len, text_bytes, text_len), llam (old) =>
    case+ old of
    | $SH.Shared() => ()
    | $SH.Cancelled() => ()
    | $SH.ShareFailed() => ())
  val () = $P.discard<$SH.text_share_answer>($SH.share_text_answer(title, title_len, text_bytes, text_len))
in () end
