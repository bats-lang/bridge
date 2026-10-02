#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload SR = "wasm.bats-packages.dev/bridge/src/scroll.sats"

(* A scroll behavior matched without Instant *)
fn f (behavior: $SR.scroll_behavior): int =
  case+ behavior of
  | $SR.Smooth() => 1
