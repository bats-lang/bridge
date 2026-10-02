#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* An app that only says it started: check.mjs loads it through the
   loader, whole, and makes the load fail in each way it can *)
implement main0 () = let
  val line = $A.alloc<byte>(7)
  val () = $A.write_text(line, 0, $A.text_lit("started"), 7)
  val @(frozen, borrowed) = $A.freeze<byte>(line)
  val () = $WI.log($WI.Info(), borrowed, 7)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
