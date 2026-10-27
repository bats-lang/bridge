#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"

(* A file share matched without FileAnswerThrown: a thrown one would go
   unhandled *)
fn f {ln:agz}{nn:pos}{lb:agz}{nb:pos}{lm:agz}{nm:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm): void =
  $P.finish<$SH.file_share_answer>($SH.share_file_answer(name, name_len, bytes, len, mime, mime_len), llam (answer) =>
    case+ answer of
    | ~$SH.FileAnswerShared() => ()
    | ~$SH.FileAnswerCancelled() => ()
    | ~$SH.FileAnswerFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.FileAnswerNotShareable() => ()
    | ~$SH.FileAnswerRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.FileAnswerCacheRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.FileAnswerUnexpected(_) => ())
