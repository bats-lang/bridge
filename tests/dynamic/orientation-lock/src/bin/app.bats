#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"
staload SC = "wasm.bats-packages.dev/bridge/src/screen.bats"

(* Locks the rotation once and says how it ended in the address's hash,
   as a line: check.mjs plays the platform (the app's plugin, a browser,
   or nothing) and prints each hash and each call. The outcome is matched
   with case+, every constructor visible. *)

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

fn say_blob {n:nat} (blob: !$BD.dblob(n)): void = let
  val n = $BD.blob_len(blob)
in
  if n <= 0 then say_text("refused:")
  else if n > 4096 then say_text("refused: long")
  else let
    val a = $A.alloc<byte>(n)
    val () = $BD.blob_read(blob, 0, a, n)
  in say(a, n) end
end

implement main0 () =
  if $SC.orientation_available() then
    $P.finish<$SC.lock_outcome>($SC.orientation_lock_current(), llam (outcome) =>
      case+ outcome of
      | ~$SC.Locked() => say_text("locked")
      | ~$SC.LockRefused(text) =>
        (case+ text of
         | ~$R.some(blob) => let val () = say_blob(blob) in $BD.blob_free(blob) end
         | ~$R.none() => say_text("refused: no text"))
      | ~$SC.LockUnavailable() => say_text("unavailable")
      | ~$SC.LockUnexpected(_) => say_text("unexpected"))
  else say_text("not offered")
