#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A handle is not a number: 0 does not name a blob *)
fn f (): int =
  case+ $BD.blob_claim(0) of
  | ~$R.none() => 0
  | ~$R.some(b) => let val () = $BD.blob_free(b) in 1 end
