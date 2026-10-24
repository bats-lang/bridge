#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.sats"

(* Signing out matched without SignOutThrown: a thrown revoke would go
   unhandled, as if the token were revoked *)
fn f (): void =
  $P.finish<$GA.sign_out_answer>($GA.google_sign_out_answer(), llam (answer) =>
    case+ answer of
    | ~$GA.SignOutDone() => ()
    | ~$GA.SignOutNotHere() => ()
    | ~$GA.SignOutRevokeFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutLoadFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutAnswerOdd(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutUnexpected(_) => ())
