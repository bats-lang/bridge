#include "share/atspre_staload.hats"
#use array as A
#use builder as BU
#use wasm.bats-packages.dev/bridge as B

(* The form with the image error atom emits more than the platform form: a
   builder with only the room of the platform form (121883 bytes) is not
   enough for it *)
fn f {n:nat | n + 121883 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 122883] $BU.builder(m)): void =
  $B.produce_bridge_image_error(b)
