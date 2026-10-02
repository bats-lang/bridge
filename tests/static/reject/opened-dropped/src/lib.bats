#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* An Opened file dropped: never closed *)
fn f (): void =
  $P.finish<$BF.opened>($BF.dropped_open_at(0), llam (found) =>
    case+ found of
    | ~$BF.Opened(_) => ()
    | ~$BF.NotOpened() => ()
    | ~$BF.OpenFailed() => ())
