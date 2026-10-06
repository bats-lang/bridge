#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BB = "wasm.bats-packages.dev/bridge/src/back_button.bats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* The page's hash set to s, which check.mjs prints *)
fn hash_text {n:pos | n < 256} (s: string n): void = let
  val a = bytes(s)
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.set_hash(borrowed, g1u2i(string1_length(s)))
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* An entry pushed onto the history, at s *)
fn push_text {n:pos | n < 256} (s: string n): void = let
  val a = bytes(s)
  val @(frozen, borrowed) = $A.freeze<byte>(a)
  val () = $NAV.push_state(borrowed, g1u2i(string1_length(s)))
  val () = $A.drop<byte>(frozen, borrowed)
in $A.free<byte>($A.thaw<byte>(frozen)) end

(* How many times Back was heard *)
val heard = ref<int>(0)

(* Whether the entry pushed was popped *)
val popped = ref<int>(0)

(* check.mjs plays the native app with its App plugin, and a browser:
   whether Back is heard is put in the hash. Each Back heard is put in
   the hash, and the second moves the app to the background. Then an
   entry is pushed and taken back (history_back), which the popstate
   callback puts in the hash *)
implement main0 () = let
  val () = (if $BB.back_button_available() then hash_text("back-heard") else hash_text("back-not-heard"))
  val () = $BB.listen_back_button(0, llam() => let
      val () = !heard := !heard + 1
    in
      if !heard = 1 then hash_text("back-1")
      else let
        val () = hash_text("back-2")
      in $BB.app_minimize() end
    end)
  val () = $NAV.set_popstate_callback(llam(url) => let
      val () = (case+ url of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
      (* the first only: setting the hash is a navigation of its own,
         which pops too *)
      val () = (if !popped = 0 then let val () = !popped := 1 in hash_text("popped") end else ())
    in 0 end)
  val () = push_text("#pushed")
in $NAV.history_back() end
