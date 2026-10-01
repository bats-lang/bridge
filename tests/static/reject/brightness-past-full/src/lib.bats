#include "share/atspre_staload.hats"
#use wasm.bats-packages.dev/bridge as B
staload SC = "wasm.bats-packages.dev/bridge/src/screen.sats"

(* 101 is past a level's bound of 100 percent *)
fn f (): void =
  if $SC.brightness_available() then $SC.brightness_set($SC.Level(101)) else ()
