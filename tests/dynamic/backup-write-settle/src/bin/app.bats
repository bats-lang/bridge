#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload BF = "wasm.bats-packages.dev/bridge/src/backup_file.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Writes the backed-up file "note" with each form and says how each ended
   in the address's hash, as a line: check.mjs prints each hash. The answer
   of backup_file_write_answer is matched with case+, every constructor
   visible, and the old backup_file_write is called too (it is kept for one
   version, bridge#236), so an edit cannot drop it: it says only written or
   not written, as it always did (bridge#186). *)

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$BF.backup_written>(_) = ()
implement $P.dispose<$BF.backup_write_answer>(answer) =
  case+ answer of
  | ~$BF.BackupWriteDone() => ()
  | ~$BF.BackupWriteNotHere() => ()
  | ~$BF.BackupWriteRejected(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$BF.BackupWriteThrown(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$BF.BackupWriteUnexpected(_) => ()

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

(* The text a write was rejected with, as the next hash after the outcome's name *)
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

fn say_answer (answer: $BF.backup_write_answer): void =
  case+ answer of
  | ~$BF.BackupWriteDone() => say_text("done")
  | ~$BF.BackupWriteNotHere() => say_text("not here")
  | ~$BF.BackupWriteRejected(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("rejected") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("rejected: no text"))
  | ~$BF.BackupWriteThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$BF.BackupWriteUnexpected(_) => say_text("unexpected")

(* s's bytes in a fresh array of exactly its length *)
fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Writes "contents" as the backed-up file "note" with the new form *)
fn write_answer (): $P.promise($BF.backup_write_answer, $P.Chained) = let
  val @(name_frozen, name_bytes) = $A.freeze<byte>(bytes("note"))
  val @(text_frozen, text_bytes) = $A.freeze<byte>(bytes("contents"))
  val answered = $BF.backup_file_write_answer(name_bytes, 4, text_bytes, 8)
  val () = $A.drop<byte>(text_frozen, text_bytes)
  val () = $A.free<byte>($A.thaw<byte>(text_frozen))
  val () = $A.drop<byte>(name_frozen, name_bytes)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in answered end

(* The same with the old form *)
fn write_old (): $P.promise($BF.backup_written, $P.Chained) = let
  val @(name_frozen, name_bytes) = $A.freeze<byte>(bytes("note"))
  val @(text_frozen, text_bytes) = $A.freeze<byte>(bytes("contents"))
  val written = $BF.backup_file_write(name_bytes, 4, text_bytes, 8)
  val () = $A.drop<byte>(text_frozen, text_bytes)
  val () = $A.free<byte>($A.thaw<byte>(text_frozen))
  val () = $A.drop<byte>(name_frozen, name_bytes)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in written end

implement main0 () =
  $P.finish<$BF.backup_write_answer>(write_answer(), llam (answer) => let
    val () = say_answer(answer)
  in
    $P.finish<$BF.backup_written>(write_old(), llam (old) =>
      case+ old of
      | $BF.BackupWritten() => say_text("old: written")
      | $BF.BackupNotWritten() => say_text("old: not written"))
  end)
