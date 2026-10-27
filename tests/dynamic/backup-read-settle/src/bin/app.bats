#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload BF = "wasm.bats-packages.dev/bridge/src/backup_file.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Reads the backed-up file "note" with each form and says how each ended
   in the address's hash, as a line: check.mjs prints each hash. The answer
   of backup_file_read_answer is matched with case+, every constructor
   visible, and the old backup_file_read is called too (it is kept for one
   version, bridge#239), so an edit cannot drop it: it says only found, none
   or unreadable, as it always did (bridge#186). *)

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$BF.backup_found>(found) =
  case+ found of
  | ~$BF.BackupFound(blob) => $BD.blob_free(blob)
  | ~$BF.BackupNone() => ()
  | ~$BF.BackupUnreadable() => ()
implement $P.dispose<$BF.backup_read_answer>(answer) =
  case+ answer of
  | ~$BF.BackupReadFound(blob) => $BD.blob_free(blob)
  | ~$BF.BackupReadNone() => ()
  | ~$BF.BackupReadNotHere() => ()
  | ~$BF.BackupReadEmpty() => ()
  | ~$BF.BackupReadRejected(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$BF.BackupReadThrown(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$BF.BackupReadUnexpected(_) => ()

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

(* A blob's bytes, as the next hash *)
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

fn say_answer (answer: $BF.backup_read_answer): void =
  case+ answer of
  | ~$BF.BackupReadFound(blob) => let val () = say_text("found") val () = say_blob(blob) in $BD.blob_free(blob) end
  | ~$BF.BackupReadNone() => say_text("none")
  | ~$BF.BackupReadNotHere() => say_text("not here")
  | ~$BF.BackupReadEmpty() => say_text("empty")
  | ~$BF.BackupReadRejected(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("rejected") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("rejected: no text"))
  | ~$BF.BackupReadThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$BF.BackupReadUnexpected(_) => say_text("unexpected")

fn name_bytes (): [l:agz] $A.arr(byte, l, 4) = let
  val a = $A.alloc<byte>(4)
  val () = $A.write_text(a, 0, $A.text_lit("note"), 4)
in a end

(* Reads the backed-up file "note" with the new form *)
fn read_answer (): $P.promise($BF.backup_read_answer, $P.Chained) = let
  val @(name_frozen, name_borrowed) = $A.freeze<byte>(name_bytes())
  val answered = $BF.backup_file_read_answer(name_borrowed, 4)
  val () = $A.drop<byte>(name_frozen, name_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in answered end

(* The same with the old form *)
fn read_old (): $P.promise($BF.backup_found, $P.Chained) = let
  val @(name_frozen, name_borrowed) = $A.freeze<byte>(name_bytes())
  val found = $BF.backup_file_read(name_borrowed, 4)
  val () = $A.drop<byte>(name_frozen, name_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in found end

implement main0 () =
  $P.finish<$BF.backup_read_answer>(read_answer(), llam (answer) => let
    val () = say_answer(answer)
  in
    $P.finish<$BF.backup_found>(read_old(), llam (old) =>
      case+ old of
      | ~$BF.BackupFound(blob) => let val () = say_text("old: found") in $BD.blob_free(blob) end
      | ~$BF.BackupNone() => say_text("old: none")
      | ~$BF.BackupUnreadable() => say_text("old: unreadable"))
  end)
