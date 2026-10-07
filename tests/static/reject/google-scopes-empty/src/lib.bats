#include "share/atspre_staload.hats"
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* No call asks for no scopes (quire#334): a list of none is not one the
   atoms take *)
fn f (scopes: $GZ.google_scopes(0)): $P.promise($GZ.google_authorization($GZ.MayAsk), $P.Chained) =
  $GZ.google_authorize_scopes(scopes)
