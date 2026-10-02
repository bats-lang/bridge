#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"

(* A listener made with lam: a closure unlisten could never free *)
fn f {lb:agz}{n:pos} (t: !$A.borrow(byte, lb, n), tn: int n): void =
  $EV.listen_document(t, tn, 1, lam (_: $EV.event_payload): int => 0)
