#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload WI = "wasm.bats-packages.dev/bridge/src/window.sats"

(* Visibility matched without Hidden *)
fn f (): int =
  case+ $WI.get_visibility() of
  | $WI.Visible() => 1
