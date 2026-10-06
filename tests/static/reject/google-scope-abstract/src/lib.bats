#include "share/atspre_staload.hats"
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* A scope is made only by google_scope_of: a string is none *)
fn f (): $P.promise($GZ.google_authorization($GZ.MayAsk), $P.Chained) =
  $GZ.google_authorize_scopes($GZ.OneScope("scope-a"))
