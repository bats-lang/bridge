#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* A scope of 255 bytes may be made *)
fn longest (): $R.option($GZ.google_scope) = $GZ.google_scope_of("sssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssssss")

(* Eight scopes may be asked for *)
fn eight (s: $GZ.google_scope): $P.promise($GZ.google_authorization($GZ.MayAsk), $P.Chained) =
  $GZ.google_authorize_scopes($GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.MoreScopes(s,
    $GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.MoreScopes(s, $GZ.OneScope(s)))))))))

(* A text of 1048576 bytes may be offered *)
fn largest {l:agz} (bytes: !$A.borrow(byte, l, 1048576)): $R.option($GZ.google_text) =
  $GZ.google_text_of(bytes, 1048576)
