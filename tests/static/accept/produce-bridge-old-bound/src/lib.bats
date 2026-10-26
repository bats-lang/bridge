#include "share/atspre_staload.hats"
#use array as A
#use builder as BU
#use wasm.bats-packages.dev/bridge as B

(* The old forms keep their old bounds (bridge-js, removal bridge#253): a
   builder with exactly 119271 (121271 for the app) bytes of room is enough
   for produce_bridge and produce_bridge_app. The forms with the platform atom
   need more (reject/produce-bridge-platform-old-room) *)
fn old_plain {n:nat | n + 119271 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 119271] $BU.builder(m)): void =
  $B.produce_bridge(b)

fn old_app {n:nat | n + 121271 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 121271] $BU.builder(m)): void =
  $B.produce_bridge_app(b, "app.wasm", "bats-root")

fn new_plain {n:nat | n + 121883 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 121883] $BU.builder(m)): void =
  $B.produce_bridge_platform(b)

fn new_app {n:nat | n + 123883 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 123883] $BU.builder(m)): void =
  $B.produce_bridge_app_platform(b, "app.wasm", "bats-root")
