#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload IE = "wasm.bats-packages.dev/bridge/src/image_error.sats"

(* A failed image let go with its node id: the blob it keeps would leak *)
fn f (failure: $IE.image_error): void =
  case+ failure of
  | ~$IE.ImageFailed(_) => ()
