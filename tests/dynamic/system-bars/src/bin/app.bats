#target wasm binary
#include "share/atspre_staload.hats"
#use wasm.bats-packages.dev/bridge as B
staload SC = "wasm.bats-packages.dev/bridge/src/screen.sats"

(* Goes into full screen, and out of it once in: check.mjs plays the
   native app's plugins and prints each call, and whether full screen is
   active after it *)
implement main0 () = let
  val () = $SC.listen_fullscreen(1, llam (change) =>
    case+ change of
    | $SC.FullscreenEntered() => $SC.fullscreen_exit()
    | $SC.FullscreenLeft() => ())
in
  if $SC.fullscreen_available() then $SC.fullscreen_enter() else ()
end
