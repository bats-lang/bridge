#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"

(* A clear_selection matched without SelectionUnavailable *)
fn f (): void =
  case+ $DR.clear_selection() of
  | $DR.SelectionCleared() => ()
