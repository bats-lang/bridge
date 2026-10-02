#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload ID = "wasm.bats-packages.dev/bridge/src/idb.sats"

(* A write matched without NotStored: a failed save would go unseen *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$ID.stored>($ID.idb_delete(borrowed, 3), llam (outcome) =>
    case+ outcome of
    | $ID.Stored() => ())
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
