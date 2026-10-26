#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Says "old form" in the address's hash, so check.mjs sees that the app
   ran under the bridge the old form produced *)
implement main0 () = let
  val a = $A.alloc<byte>(8)
  val () = $A.write_text(a, 0, $A.text_lit("old form"), 8)
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, 8)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
