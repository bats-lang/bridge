#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload IE = "wasm.bats-packages.dev/bridge/src/image_error.sats"

(* A failed image taken apart in its one case, the node id's blob freed *)
fn failed (failure: $IE.image_error): void =
  case+ failure of
  | ~$IE.ImageFailed(id) => $DC.blob_free(id)

(* The listener takes a linear closure made with llam, and the atom says
   whether it is there *)
fn f (): void = let
  val () = $IE.listen_image_error(0, llam(failure) => failed(failure))
in if $IE.image_error_available() then () else () end
