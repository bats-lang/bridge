#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload GZ = "wasm.bats-packages.dev/bridge/src/google_authorize.sats"

(* A caller's own bytes are no token: a blank one cannot be cleared
   (quire#334). The atom takes a google_text, which google_text_of makes
   only from bytes holding a visible character *)
fn f {l:agz} (blank: !$A.borrow(byte, l, 1)): $P.promise($GZ.google_authorization_change, $P.Chained) =
  $GZ.google_clear_token(blank)
