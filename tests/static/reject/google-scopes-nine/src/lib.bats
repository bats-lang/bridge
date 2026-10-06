#include "share/atspre_staload.hats"
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* A call asks for at most 8 scopes: nine cannot be asked for *)
fn f (s: $GZ.google_scope): $P.promise($GZ.google_authorization($GZ.MayAsk), $P.Chained) =
  $GZ.google_authorize_scopes($GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.MoreScopes(s,
    $GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.OneScope(s))))))))))
