#include "share/atspre_staload.hats"
#use wasm.bats-packages.dev/bridge as B
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* Needs a value below 2^30 *)
fn below_2_30 {v:nat | v < 1073741824} (v: int v): int v = v

(* epoch_millis's low part is below 2^30 by its type *)
fn f (): int = let
  val @(high, low) = $TM.epoch_millis()
in high + below_2_30(low) end
