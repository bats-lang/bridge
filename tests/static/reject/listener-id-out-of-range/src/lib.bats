#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"

(* There are 128 listener slots: 128 is not one *)
fn f {lb:agz}{n:pos} (t: !$A.borrow(byte, lb, n), tn: int n): void =
  $EV.listen_document(t, tn, 128, lam (_: $EV.event_payload): int => 0)
