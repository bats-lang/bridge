#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload EV = "wasm.bats-packages.dev/bridge/src/event.bats"
staload WI = "wasm.bats-packages.dev/bridge/src/window.bats"

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Wants the screen awake; a "sleep" event on the document lets it
   sleep again. check.mjs plays the browser: it grants each lock, drops
   it when it hides the page, and counts the requests and releases *)
implement main0 () = let
  val () = $WI.keep_awake(true)
  val @(sleep_frozen, sleep) = $A.freeze<byte>(bytes("sleep"))
  val () = $EV.listen_document(sleep, 5, 0, llam (_) => let
    val () = $WI.keep_awake(false) in 0 end)
  val () = $A.drop<byte>(sleep_frozen, sleep)
in $A.free<byte>($A.thaw<byte>(sleep_frozen)) end
