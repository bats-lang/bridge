#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload NO = "wasm.bats-packages.dev/bridge/src/notify.sats"

(* A permission matched without NotAsked *)
fn f (): void =
  $P.finish<$NO.permission>($NO.notify_request_permission(), llam (answer) =>
    case+ answer of
    | $NO.Granted() => ()
    | $NO.Denied() => ())
