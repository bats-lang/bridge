#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload ME = "wasm.bats-packages.dev/bridge/src/media.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

fn say {n:pos | n < 256} (line: string n): void = let
  val n = g1u2i(string1_length(line))
  val bytes = $A.alloc<byte>(n)
  val () = $A.write_text(bytes, 0, $A.text_lit(line), n)
  val @(frozen, borrowed) = $A.freeze<byte>(bytes)
  val () = $WI.log($WI.Info(), borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* Logs each end of a font load, and where the fonts stand then.
   check.mjs plays document.fonts *)
implement main0 () =
  $ME.listen_fonts_loaded(3, llam (status) =>
    case+ status of
    | $ME.FontsSettled() => say("fonts loaded, none loading")
    | $ME.FontsStillLoading() => say("fonts loaded, others loading"))
