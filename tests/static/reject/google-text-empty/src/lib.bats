#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* A token or an account is at least one byte: none cannot be made one *)
fn f {l:agz} (bytes: !$A.borrow(byte, l, 0)): $R.option($GZ.google_text) =
  $GZ.google_text_of(bytes, 0)
