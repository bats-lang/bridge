#target wasm binary
#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload SH = "wasm.bats-packages.dev/bridge/src/share.bats"
staload NAV = "wasm.bats-packages.dev/bridge/src/nav.bats"

(* Shares the file "a/b.txt" (type text/plain, holding "data") with
   share_file_answer and then, again, with the old share_file, and says how
   each ended in the address's hash, as a line: check.mjs prints each hash.
   The answer of share_file_answer is matched with case+, every constructor
   visible, and the old share_file is called too (it is kept for one
   version, bridge#242), so an edit cannot drop it: it says only shared,
   cancelled, failed or not shareable, as it always did (bridge#186). *)

(* Answers nobody took, freed: before their first use *)
implement $P.dispose<$SH.file_share_outcome>(_) = ()
implement $P.dispose<$SH.file_share_answer>(answer) =
  case+ answer of
  | ~$SH.FileAnswerShared() => ()
  | ~$SH.FileAnswerCancelled() => ()
  | ~$SH.FileAnswerFailed(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$SH.FileAnswerNotShareable() => ()
  | ~$SH.FileAnswerRejected(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$SH.FileAnswerCacheRejected(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$SH.FileAnswerThrown(text) => (case+ text of ~$R.some(blob) => $BD.blob_free(blob) | ~$R.none() => ())
  | ~$SH.FileAnswerUnexpected(_) => ()

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

fn say_answer (answer: $SH.file_share_answer): void =
  case+ answer of
  | ~$SH.FileAnswerShared() => say_text("shared")
  | ~$SH.FileAnswerCancelled() => say_text("cancelled")
  | ~$SH.FileAnswerFailed(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("failed") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("failed: no text"))
  | ~$SH.FileAnswerNotShareable() => say_text("not shareable")
  | ~$SH.FileAnswerRejected(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("rejected") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("rejected: no text"))
  | ~$SH.FileAnswerCacheRejected(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("cache rejected") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("cache rejected: no text"))
  | ~$SH.FileAnswerThrown(text) =>
    (case+ text of
     | ~$R.some(blob) => let val () = say_text("thrown") val () = say_blob(blob) in $BD.blob_free(blob) end
     | ~$R.none() => say_text("thrown: no text"))
  | ~$SH.FileAnswerUnexpected(_) => say_text("unexpected")

fn say_old (old: $SH.file_share_outcome): void =
  case+ old of
  | $SH.FileShared() => say_text("old: shared")
  | $SH.FileShareCancelled() => say_text("old: cancelled")
  | $SH.FileShareFailed() => say_text("old: failed")
  | $SH.FilesNotShareable() => say_text("old: not shareable")

fn bytes {n:pos | n < 256} (s: string n): [l:agz] $A.arr(byte, l, n) = let
  val n = g1u2i(string1_length(s))
  val a = $A.alloc<byte>(n)
  val () = $A.write_text(a, 0, $A.text_lit(s), n)
in a end

(* Shares the file with the new form *)
fn share_answer (): $P.promise($SH.file_share_answer, $P.Chained) = let
  val @(name_frozen, name_borrowed) = $A.freeze<byte>(bytes("a/b.txt"))
  val @(data_frozen, data_borrowed) = $A.freeze<byte>(bytes("data"))
  val @(mime_frozen, mime_borrowed) = $A.freeze<byte>(bytes("text/plain"))
  val answered = $SH.share_file_answer(name_borrowed, 7, data_borrowed, 4, mime_borrowed, 10)
  val () = $A.drop<byte>(mime_frozen, mime_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(mime_frozen))
  val () = $A.drop<byte>(data_frozen, data_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(data_frozen))
  val () = $A.drop<byte>(name_frozen, name_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in answered end

(* The same with the old form *)
fn share_old (): $P.promise($SH.file_share_outcome, $P.Chained) = let
  val @(name_frozen, name_borrowed) = $A.freeze<byte>(bytes("a/b.txt"))
  val @(data_frozen, data_borrowed) = $A.freeze<byte>(bytes("data"))
  val @(mime_frozen, mime_borrowed) = $A.freeze<byte>(bytes("text/plain"))
  val outcome = $SH.share_file(name_borrowed, 7, data_borrowed, 4, mime_borrowed, 10)
  val () = $A.drop<byte>(mime_frozen, mime_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(mime_frozen))
  val () = $A.drop<byte>(data_frozen, data_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(data_frozen))
  val () = $A.drop<byte>(name_frozen, name_borrowed)
  val () = $A.free<byte>($A.thaw<byte>(name_frozen))
in outcome end

implement main0 () =
  $P.finish<$SH.file_share_answer>(share_answer(), llam (answer) => let
    val () = say_answer(answer)
  in
    $P.finish<$SH.file_share_outcome>(share_old(), llam (old) => say_old(old))
  end)
