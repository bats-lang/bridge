#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/backup_file.sats"

(* A write matched in every case, its text freed; the old form matched too
   (kept for one version, bridge#236); an answer let go is freed by its
   dispose *)
fn f {ln:agz}{nn:pos}{lb:agz}{nb:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb): void = let
  val () = $P.finish<$BF.backup_write_answer>($BF.backup_file_write_answer(name, name_len, bytes, len), llam (answer) =>
    case+ answer of
    | ~$BF.BackupWriteDone() => ()
    | ~$BF.BackupWriteNotHere() => ()
    | ~$BF.BackupWriteRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BF.BackupWriteThrown(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BF.BackupWriteUnexpected(_) => ())
  val () = $P.finish<$BF.backup_written>($BF.backup_file_write(name, name_len, bytes, len), llam (old) =>
    case+ old of
    | $BF.BackupWritten() => ()
    | $BF.BackupNotWritten() => ())
  val () = $P.discard<$BF.backup_write_answer>($BF.backup_file_write_answer(name, name_len, bytes, len))
in () end
