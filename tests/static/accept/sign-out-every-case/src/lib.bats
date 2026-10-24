#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload GA = "wasm.bats-packages.dev/bridge/src/google_account.sats"

(* Signing out matched in every case, its text freed; the old form matched
   too (kept for one version, bridge#231); an answer let go is freed by its
   dispose *)
fn f (): void = let
  val () = $P.finish<$GA.sign_out_answer>($GA.google_sign_out_answer(), llam (answer) =>
    case+ answer of
    | ~$GA.SignOutDone() => ()
    | ~$GA.SignOutNotHere() => ()
    | ~$GA.SignOutRevokeFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutLoadFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutThrown(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutAnswerOdd(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutAnswerUnread(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$GA.SignOutUnexpected(_) => ())
  val () = $P.finish<$GA.google_signed_out>($GA.google_sign_out(), llam (old) =>
    case+ old of
    | $GA.GoogleSignedOut() => ()
    | $GA.GoogleSignOutFailed() => ())
  val () = $P.discard<$GA.sign_out_answer>($GA.google_sign_out_answer())
in () end
