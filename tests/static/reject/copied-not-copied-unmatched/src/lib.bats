#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload CL = "wasm.bats-packages.dev/bridge/src/clipboard.sats"

(* A copy matched without NotCopied *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("lib"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$CL.copied>($CL.clipboard_write(borrowed, 3), llam (outcome) =>
    case+ outcome of
    | $CL.Copied() => ())
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
