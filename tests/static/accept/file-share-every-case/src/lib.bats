#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"

(* A file share matched in every case, its text freed; the old form matched too
   (kept for one version, bridge#242); an answer let go is freed by its
   dispose *)
fn f {ln:agz}{nn:pos}{lb:agz}{nb:pos}{lm:agz}{nm:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm): void = let
  val () = $P.finish<$SH.file_share_answer>($SH.share_file_answer(name, name_len, bytes, len, mime, mime_len), llam (answer) =>
    case+ answer of
    | ~$SH.FileAnswerShared() => ()
    | ~$SH.FileAnswerCancelled() => ()
    | ~$SH.FileAnswerFailed(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.FileAnswerNotShareable() => ()
    | ~$SH.FileAnswerRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.FileAnswerCacheRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.FileAnswerThrown(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$SH.FileAnswerUnexpected(_) => ())
  val () = $P.finish<$SH.file_share_outcome>($SH.share_file(name, name_len, bytes, len, mime, mime_len), llam (old) =>
    case+ old of
    | $SH.FileShared() => ()
    | $SH.FileShareCancelled() => ()
    | $SH.FileShareFailed() => ()
    | $SH.FilesNotShareable() => ())
  val () = $P.discard<$SH.file_share_answer>($SH.share_file_answer(name, name_len, bytes, len, mime, mime_len))
in () end
