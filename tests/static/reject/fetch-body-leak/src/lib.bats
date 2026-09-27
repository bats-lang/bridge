#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A claimed body must be freed *)
fn f (h: Int): int =
  case+ $FE.fetch_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(@(s, b)) => s
