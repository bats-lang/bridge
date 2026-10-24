#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.sats"

(* A thrown revoke's text not freed: the text is a linear blob *)
fn f (): void =
  $P.finish<$GA.sign_out_answer>($GA.google_sign_out_answer(), llam (answer) =>
    case+ answer of
    | ~$GA.SignOutDone() => ()
    | ~$GA.SignOutNotHere() => ()
    | ~$GA.SignOutRevokeFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutLoadFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutThrown(text) => ()
    | ~$GA.SignOutAnswerOdd(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutAnswerUnread(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutUnexpected(_) => ())
