#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"
staload SC = "wasm.bats-packages.dev/bridge/src/screen.bats"

(* Reads the screen's brightness once and says how it ended in the
   address's hash, as a line: check.mjs plays the app's ScreenBrightness
   plugin and prints each hash. The reading is matched with case+, every
   constructor visible. A read whose plugin answer makes the bridge's ok
   handler throw must still settle: the app says unreadable, not nothing. *)

fn say {l:agz}{n:pos | n <= 4096} (a: $A.arr(byte, l, n), n: int n): void = let
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

fn say_text {n:pos | n < 256} (s: string n): void = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in say(a, n) end

implement main0 () =
  if $SC.brightness_available() then
    $P.finish<$SC.brightness_reading>($SC.brightness_get(), llam (reading) =>
      case+ reading of
      | ~$SC.Brightness(_) => say_text("brightness")
      | ~$SC.SystemBrightness() => say_text("system")
      | ~$SC.BrightnessUnreadable() => say_text("unreadable"))
  else say_text("not offered")
