#include "share/atspre_staload.hats"
#use array as A
#use builder as BU
#use wasm.bats-packages.dev/bridge as B

(* The form with the platform atom emits more than the old bound: a builder
   with only the old room (119271 bytes) is not enough for it *)
fn f {n:nat | n + 119271 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 121883] $BU.builder(m)): void =
  $B.produce_bridge_platform(b)
