#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"

(* A measure matched without NoElement *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = (case+ $DR.measure(borrowed, 3) of
    | $DR.Measured() => ())
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
