#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/backup_file.sats"

(* A read matched in every case, its text freed; the old form matched too
   (kept for one version, bridge#239); an answer let go is freed by its
   dispose *)
fn f {ln:agz}{nn:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn): void = let
  val () = $P.finish<$BF.backup_read_answer>($BF.backup_file_read_answer(name, name_len), llam (answer) =>
    case+ answer of
    | ~$BF.BackupReadFound(blob) => $DC.blob_free(blob)
    | ~$BF.BackupReadNone() => ()
    | ~$BF.BackupReadNotHere() => ()
    | ~$BF.BackupReadEmpty() => ()
    | ~$BF.BackupReadRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BF.BackupReadThrown(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BF.BackupReadUnexpected(_) => ())
  val () = $P.finish<$BF.backup_found>($BF.backup_file_read(name, name_len), llam (old) =>
    case+ old of
    | ~$BF.BackupFound(blob) => $DC.blob_free(blob)
    | ~$BF.BackupNone() => ()
    | ~$BF.BackupUnreadable() => ())
  val () = $P.discard<$BF.backup_read_answer>($BF.backup_file_read_answer(name, name_len))
in () end
