#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* A caller's own bytes are no scope: a blank one cannot be asked for
   (quire#334). The atoms take google_scopes, whose texts only bridge
   writes *)
fn f {l:agz} (blank: !$A.borrow(byte, l, 1)): $P.promise($GZ.google_authorization($GZ.MayAsk), $P.Chained) =
  $GZ.google_authorize_scopes(blank)
