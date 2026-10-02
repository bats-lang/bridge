#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload ID = "wasm.bats-packages.dev/bridge/src/idb.sats"

(* A Found blob dropped: JS would keep its bytes, and nothing frees them *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$ID.lookup>($ID.idb_get(borrowed, 3), llam (found) =>
    case+ found of
    | ~$ID.Found(_) => ()
    | ~$ID.Absent() => ()
    | ~$ID.Unreadable() => ())
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
