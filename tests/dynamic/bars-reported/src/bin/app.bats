#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload SC = "wasm.bats-packages.dev/bridge/src/screen.sats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* The page's hash set to s, which check.mjs prints *)
fn hash_text {n:pos | n < 256} (s: string n): void = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* check.mjs plays the native side's reports (batsNative.systemBars):
   whether they are available is put in the hash, then each report the
   listener is passed, the one made before it first *)
implement main0 () = let
  val () = (if $SC.system_bars_available() then hash_text("available") else hash_text("unavailable"))
in
  $SC.listen_system_bars(0, llam(bars) =>
    case+ bars of
    | $SC.BarsShown() => hash_text("both-shown")
    | $SC.StatusBarShown() => hash_text("status-bar-shown")
    | $SC.NavigationBarShown() => hash_text("navigation-bar-shown")
    | $SC.BarsHidden() => hash_text("both-hidden"))
end
