#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A fetched body claimed as a file must be closed, so JS lets go of it *)
fn f (h: Int): int =
  case+ $FE.fetch_claim_file(h) of
  | ~$R.none() => 0
  | ~$R.some(@(_, fl)) => $BF.file_size(fl)
