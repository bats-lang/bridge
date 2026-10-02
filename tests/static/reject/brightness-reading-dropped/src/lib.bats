#include "share/atspre_staload.hats"
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload SC = "wasm.bats-packages.dev/bridge/src/screen.sats"

(* A reading dropped without being taken apart: Brightness is boxed,
   and wasm has no garbage collector, so it would leak *)
fn f (): void =
  $P.finish<$SC.brightness_reading>($SC.brightness_get(), llam (reading) => ())
