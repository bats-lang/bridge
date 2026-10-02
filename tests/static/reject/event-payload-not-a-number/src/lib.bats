#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload EV = "wasm.bats-packages.dev/bridge/src/event.sats"

(* A payload is not a number: it cannot be compared with 0 to ask
   whether the event has bytes (event_take answers that) *)
fn f {lb:agz}{n:pos} (t: !$A.borrow(byte, lb, n), tn: int n): void =
  $EV.listen_document(t, tn, 0, llam (payload) => if payload = 0 then 0 else 1)
