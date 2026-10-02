#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A body fetched as a file must be closed, so JS lets go of it *)
fn f (got: $FE.fetched_file): int =
  case+ got of
  | ~$FE.NoFileResponse() => 0
  | ~$FE.RespondedFile(_, fl) => $BF.file_size(fl)
