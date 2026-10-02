#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use wasm.bats-packages.dev/bridge as B
staload BW = "wasm.bats-packages.dev/bridge/src/build_watch.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Logs a line of n bytes at info *)
fn say {n:pos | n < 256} (line: string n): void = let
  val n = g1u2i(string1_length(line))
  val @(frozen, borrowed) = $A.freeze<byte>(bytes(line))
  val () = $WI.log($WI.Info(), borrowed, n)
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* Logs what a watch found: new_build or ended *)
fn show {nn,ne:pos | nn < 256; ne < 256} (new_build: string nn, ended: string ne, change: $BW.build_change): void =
  case+ change of
  | $BW.NewBuild() => say(new_build)
  | $BW.WatchEnded() => say(ended)

(* Watches app.wasm (check.mjs serves it with an ETag that changes on
   the third check) and plain.wasm (served with no stamp) *)
implement main0 () = let
  val @(app_frozen, app) = $A.freeze<byte>(bytes("app.wasm"))
  val () = $P.finish<$BW.build_change>($BW.build_watch(app, 8), llam (change) => show("app: new build", "app: watch ended", change))
  val () = $A.drop<byte>(app_frozen, app)
  val () = $A.free<byte>($A.thaw<byte>(app_frozen))
  val @(plain_frozen, plain) = $A.freeze<byte>(bytes("plain.wasm"))
  val () = $P.finish<$BW.build_change>($BW.build_watch(plain, 10), llam (change) => show("plain: new build", "plain: watch ended", change))
  val () = $A.drop<byte>(plain_frozen, plain)
in $A.free<byte>($A.thaw<byte>(plain_frozen)) end
