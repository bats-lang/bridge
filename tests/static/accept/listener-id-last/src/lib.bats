#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"

(* The last of the 128 listener slots *)
fn f {lb:agz}{n:pos} (t: !$A.borrow(byte, lb, n), tn: int n): void =
  $EV.listen_document(t, tn, 127, lam (_: $EV.event_payload): int => 0)
