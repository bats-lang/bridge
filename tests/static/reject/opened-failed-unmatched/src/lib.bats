#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* A file open matched without OpenFailed *)
fn f (): void = let
  val key = $A.alloc<byte>(3)
  val () = $A.write_text(key, 0, $A.text_lit("abc"), 3)
  val @(frozen, borrowed) = $A.freeze<byte>(key)
  val () = $P.finish<$BF.opened>($BF.file_open(borrowed, 3), llam (found) =>
    case+ found of
    | ~$BF.Opened(f) => $BF.file_close(f)
    | ~$BF.NotOpened() => ())
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end
