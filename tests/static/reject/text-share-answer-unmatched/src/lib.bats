#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"

(* A text share matched without TextAnswerThrown: a thrown one would go
   unhandled *)
fn f {lt:agz}{nt:pos}{kt:nat | kt <= nt}{lx:agz}{nx:pos}
  (title: !$A.borrow(byte, lt, nt), title_len: int kt,
   text_bytes: !$A.borrow(byte, lx, nx), text_len: int nx): void =
  $P.finish<$SH.text_share_answer>($SH.share_text_answer(title, title_len, text_bytes, text_len), llam (answer) =>
    case+ answer of
    | ~$SH.TextAnswerShared() => ()
    | ~$SH.TextAnswerCancelled() => ()
    | ~$SH.TextAnswerFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.TextAnswerNotHere() => ()
    | ~$SH.TextAnswerRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.TextAnswerUnexpected(_) => ())
