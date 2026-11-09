#include "share/atspre_staload.hats"
#use array as A
#use builder as BU
#use wasm.bats-packages.dev/bridge as B

(* The book forms (book content, outside reads) have their own bounds, and the
   old forms keep theirs (the overlap rule, bridge#253): a builder with exactly
   142344 bytes of room (144344 for the app) is enough for produce_bridge_book
   and produce_bridge_app_book, and the old produce_bridge_app still fits its
   121271 *)
fn old_app {n:nat | n + 121271 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 121271] $BU.builder(m)): void =
  $B.produce_bridge_app(b, "app.wasm", "bats-root")

fn book_plain {n:nat | n + 142344 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 142344] $BU.builder(m)): void =
  $B.produce_bridge_book(b)

fn book_app {n:nat | n + 144344 <= $BU.BUILDER_CAP}
  (b: !$BU.builder(n) >> [m:nat | n <= m; m <= n + 144344] $BU.builder(m)): void =
  $B.produce_bridge_app_book(b, "app.wasm", "bats-root")
