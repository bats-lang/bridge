#include "share/atspre_staload.hats"
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* A scope is under 256 bytes: a text of 256 cannot be made one *)
fn f (): $R.option($GZ.google_scope) = $GZ.google_scope_of("ssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss")
