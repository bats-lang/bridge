#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"

(* A select_range matched without SelectionRefused (or NoSuchElement) *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val @(frozen2, borrowed2) = $A.freeze<byte>($A.alloc<byte>(3))
  val () = (case+ $DR.select_range(borrowed, 3, 0, borrowed2, 3, 1) of
    | $DR.RangeSelected() => ())
  val () = $A.drop<byte>(frozen2, borrowed2)
  val () = $A.free<byte>($A.thaw<byte>(frozen2))
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
