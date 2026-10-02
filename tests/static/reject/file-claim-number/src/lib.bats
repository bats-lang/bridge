#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A handle is not a number: 0 does not name a file *)
fn f (): int =
  case+ $BF.file_claim(0) of
  | ~$R.none() => 0
  | ~$R.some(fl) => let val () = $BF.file_close(fl) in 1 end
