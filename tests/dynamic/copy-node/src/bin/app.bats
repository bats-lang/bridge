#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload DM = "wasm.bats-packages.dev/bridge/src/dom.bats"

(* Copies element "page" into element "sheet" (check.mjs made both),
   then into "sheet" again, and copies an element that is not there *)
implement main0 () = let
  val source = $A.alloc<byte>(4)
  val () = $A.write_text(source, 0, $A.text_lit("page"), 4)
  val holder = $A.alloc<byte>(5)
  val () = $A.write_text(holder, 0, $A.text_lit("sheet"), 5)
  val missing = $A.alloc<byte>(7)
  val () = $A.write_text(missing, 0, $A.text_lit("nowhere"), 7)
  val @(source_frozen, source_bytes) = $A.freeze<byte>(source)
  val @(holder_frozen, holder_bytes) = $A.freeze<byte>(holder)
  val @(missing_frozen, missing_bytes) = $A.freeze<byte>(missing)
  val () = $DM.copy_node(source_bytes, 4, holder_bytes, 5)
  (* again: the first copy is replaced, not added to *)
  val () = $DM.copy_node(source_bytes, 4, holder_bytes, 5)
  (* nothing to copy: the holder is left as it is *)
  val () = $DM.copy_node(missing_bytes, 7, holder_bytes, 5)
  val () = $A.drop<byte>(source_frozen, source_bytes)
  val () = $A.drop<byte>(holder_frozen, holder_bytes)
  val () = $A.drop<byte>(missing_frozen, missing_bytes)
  val () = $A.free<byte>($A.thaw<byte>(source_frozen))
  val () = $A.free<byte>($A.thaw<byte>(holder_frozen))
in $A.free<byte>($A.thaw<byte>(missing_frozen)) end
