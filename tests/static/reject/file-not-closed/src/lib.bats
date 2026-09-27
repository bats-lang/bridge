#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A claimed file must be closed, so JS lets go of its bytes *)
fn f (h: Int): int =
  case+ $BF.file_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(fl) => $BF.file_size(fl)
