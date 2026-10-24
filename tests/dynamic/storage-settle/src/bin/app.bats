#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"
staload ST = "wasm.bats-packages.dev/bridge/src/storage.bats"

(* Asks whether the app's storage is kept with each form and says how each
   ended in the address's hash, as a line: check.mjs plays navigator.storage
   and prints each hash. The answer of storage_persisted_answer is matched
   with case+, every constructor visible, and the old storage_persisted is
   called too (it is kept for one version, bridge#227), so an edit cannot
   drop it: it says only yes or no, a rejection is no, as it always was
   (bridge#186). *)

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

(* The text a call rejected with, as the next hash after the outcome's name *)
fn say_blob {n:nat} (blob: !$BD.dblob(n)): void = let
  val n = $BD.blob_len(blob)
in
  if n <= 0 then say_text("no text")
  else if n > 4096 then say_text("long text")
  else let
    val a = $A.alloc<byte>(n)
    val () = $BD.blob_read(blob, 0, a, n)
  in say(a, n) end
end

fn say_answer (answer: $ST.persist_answer): void =
  case+ answer of
  | ~$ST.PersistKept() => say_text("kept")
  | ~$ST.PersistNotKept() => say_text("not kept")
  | ~$ST.PersistRefused(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("refused") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("refused: no text"))
  | ~$ST.PersistAnswerOdd(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("odd") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("odd: no text"))
  | ~$ST.PersistUnexpected(_) => say_text("unexpected")

implement main0 () = let
  val () = $P.finish<$ST.persist_answer>($ST.storage_persisted_answer(), llam (answer) =>
    say_answer(answer))
in
  $P.finish<$ST.persist_outcome>($ST.storage_persisted(), llam (old) =>
    case+ old of
    | $ST.Persisted() => say_text("old: persisted")
    | $ST.NotPersisted() => say_text("old: not persisted"))
end
