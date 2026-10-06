#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* An empty scope cannot be made (quire#334): its text's length must be
   positive *)
fn f (): $R.option($GZ.google_scope) = $GZ.google_scope_of("")
