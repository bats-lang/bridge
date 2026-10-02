#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload SH = "wasm.bats-packages.dev/bridge/src/share.sats"

(* A share's end is matched without Cancelled: a closed share sheet
   would go unhandled *)
fn f (): void = let
  val text = $A.alloc<byte>(2)
  val () = $A.write_text(text, 0, $A.text_lit("Hi"), 2)
  val @(frozen, borrowed) = $A.freeze<byte>(text)
  val title = $A.dup<byte>(frozen, borrowed)
  val () = $P.finish<$SH.share_outcome>($SH.share_text(title, 0, borrowed, 2), llam (outcome) =>
    case+ outcome of
    | $SH.Shared() => ()
    | $SH.ShareFailed() => ())
  val () = $A.drop<byte>(frozen, title)
  val () = $A.drop<byte>(frozen, borrowed)
  val () = $A.free<byte>($A.thaw<byte>(frozen))
in end
