#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/backup_file.sats"

(* A thrown write's text not freed: the text is a linear blob *)
fn f {ln:agz}{nn:pos}{lb:agz}{nb:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb): void =
  $P.finish<$BF.backup_write_answer>($BF.backup_file_write_answer(name, name_len, bytes, len), llam (answer) =>
    case+ answer of
    | ~$BF.BackupWriteDone() => ()
    | ~$BF.BackupWriteNotHere() => ()
    | ~$BF.BackupWriteRejected(text) => (case+ text of ~$R.some(blob) => $DC.blob_free(blob) | ~$R.none() => ())
    | ~$BF.BackupWriteThrown(text) => ()
    | ~$BF.BackupWriteUnexpected(_) => ())
