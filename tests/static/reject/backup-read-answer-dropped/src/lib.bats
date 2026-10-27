#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/backup_file.sats"

(* A read's thrown text not freed: the text is a linear blob *)
fn f {ln:agz}{nn:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn): void =
  $P.finish<$BF.backup_read_answer>($BF.backup_file_read_answer(name, name_len), llam (answer) =>
    case+ answer of
    | ~$BF.BackupReadFound(blob) => $DC.blob_free(blob)
    | ~$BF.BackupReadNone() => ()
    | ~$BF.BackupReadNotHere() => ()
    | ~$BF.BackupReadEmpty() => ()
    | ~$BF.BackupReadRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BF.BackupReadThrown(text) => ()
    | ~$BF.BackupReadUnexpected(_) => ())
