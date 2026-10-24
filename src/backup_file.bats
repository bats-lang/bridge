(* backup_file -- files the system backs up for the app

   App (Capacitor) only: files in the app's own files directory, under
   backup/ (BACKUP_DIRECTORY), through the Filesystem plugin
   (plugins.bats). Android's Auto Backup keeps that directory and
   nothing else of the app's (backup_rules, the rules pwa writes into the
   app's manifest), and gives it back when the app is installed again
   (on a new device, or after a reinstall). It is a backup, not a sync:
   the system backs up about once a day, idle and on Wi-Fi. *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use builder as B
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* How a write ended. Deprecated (backup_file, bridge#236): it folds no
   plugin here, a write the plugin rejected and a write that threw into
   BackupNotWritten, and any answer of the plugin into BackupWritten;
   backup_write_answer tells them apart. *)
#pub datatype backup_written =
  | BackupWritten
  | BackupNotWritten  (* no plugin here, or the write failed *)

(* How a write ended, each outcome its own. JS's answer is decoded here,
   once: the plugin wrote the file, no plugin here, the plugin rejected the
   write (what, as text), the write threw (what, as text: the call, or
   reading the name or the bytes), and a code JS never gives. The text is
   none when JS could not write it down. Linear (the text), so the one
   consumer takes it apart with case+ ~; one no consumer takes is freed by
   promise's dispose. *)
#pub datavtype backup_write_answer =
  | BackupWriteDone                                          (* the plugin wrote the file *)
  | BackupWriteNotHere                                       (* no plugin here *)
  | BackupWriteRejected of $R.option([n:nat] dblob(n))       (* the plugin rejected the write: what, as text *)
  | BackupWriteThrown of $R.option([n:nat] dblob(n))         (* the write threw: what, as text *)
  | BackupWriteUnexpected of Int                             (* a code JS never gives *)

(* What reading a backed-up file found. None and unreadable are told
   apart: BackupNone is no such file; BackupUnreadable is one that could
   not be read (or no plugin here). Linear: BackupFound holds the bytes
   as a blob JS keeps until it is freed. *)
#pub datavtype backup_found =
  | BackupFound of ([n:pos] dblob(n))
  | BackupNone
  | BackupUnreadable

(* Whether backed-up files can be kept here: the app, with its plugin *)
#pub fun backup_file_available(): bool

(* Writes bytes[0, len) as the backed-up file name[0, name_len) (a plain
   name: a '/' or '\' in it is made '_'), replacing it.
   Deprecated (backup_file, bridge#236): backup_file_write_answer. *)
#pub fun backup_file_write
  {ln:agz}{nn:pos}{lb:agz}{nb:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb)
  : $P.promise(backup_written, $P.Chained)

(* backup_file_write with every outcome its own *)
#pub fun backup_file_write_answer
  {ln:agz}{nn:pos}{lb:agz}{nb:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb)
  : $P.promise(backup_write_answer, $P.Chained)

(* Reads the backed-up file name[0, name_len) *)
#pub fun backup_file_read
  {ln:agz}{nn:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn)
  : $P.promise(backup_found, $P.Chained)

(* The directory, in the app's files directory, that backed-up files are
   kept in and that the system backs up *)
#pub fn backup_directory (): string 7

(* The backup rules of the app's manifest, for Android 11 and lower
   (android:fullBackupContent): backup/ only *)
#pub fn put_full_backup_content {n:nat | n + 200 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 200] $B.builder(m)): void

(* The same for Android 12 and higher (android:dataExtractionRules): to
   the cloud and to a new device, backup/ only *)
#pub fn put_data_extraction_rules {n:nat | n + 400 <= $B.BUILDER_CAP}
  (b: !$B.builder(n) >> [m:nat | n <= m; m <= n + 400] $B.builder(m)): void

implement backup_directory () = "backup/"

implement put_full_backup_content (b) = let
  val () = $B.bput(b, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
  val () = $B.bput(b, "<full-backup-content>\n")
  val () = $B.bput(b, "    <include domain=\"file\" path=\"")
  val () = $B.bput(b, backup_directory())
  val () = $B.bput(b, "\" />\n")
in $B.bput(b, "</full-backup-content>\n") end

implement put_data_extraction_rules (b) = let
  val () = $B.bput(b, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
  val () = $B.bput(b, "<data-extraction-rules>\n")
  val () = $B.bput(b, "    <cloud-backup>\n")
  val () = $B.bput(b, "        <include domain=\"file\" path=\"")
  val () = $B.bput(b, backup_directory())
  val () = $B.bput(b, "\" />\n")
  val () = $B.bput(b, "    </cloud-backup>\n")
  val () = $B.bput(b, "    <device-transfer>\n")
  val () = $B.bput(b, "        <include domain=\"file\" path=\"")
  val () = $B.bput(b, backup_directory())
  val () = $B.bput(b, "\" />\n")
  val () = $B.bput(b, "    </device-transfer>\n")
in $B.bput(b, "</data-extraction-rules>\n") end

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

$UNSAFE begin
%{
extern int bats_js_backup_file_available(void);
extern void bats_js_backup_file_write(void*, int, void*, int, int);
extern int bats_js_backup_file_write_text(int);
extern void bats_js_backup_file_read(void*, int, int);
%}
extern fun _bats_js_backup_file_available
  (): int = "mac#bats_js_backup_file_available"
extern fun _bats_js_backup_file_write
  (name: ptr, name_len: int, bytes: ptr, len: int, resolver_id: int)
  : void = "mac#bats_js_backup_file_write"
extern fun _bats_js_backup_file_write_text
  (resolver_id: int): int = "mac#bats_js_backup_file_write_text"
extern fun _bats_js_backup_file_read
  (name: ptr, name_len: int, resolver_id: int)
  : void = "mac#bats_js_backup_file_read"
end

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

(* JS's codes: the file's blob (positive), 0 no such file, anything else
   unreadable. A handle JS did not hand out, or an empty blob, is
   unreadable too *)
fn _backup_found (code: Int): backup_found =
  if code = 0 then BackupNone()
  else if code < 0 then BackupUnreadable()
  else (case+ _claimed(code) of
    | ~$R.some(blob) =>
      if blob_len(blob) > 0 then BackupFound(blob)
      else let val () = blob_free(blob) in BackupUnreadable() end
    | ~$R.none() => BackupUnreadable())

(* What the plugin rejected the write with, or what threw, as text: JS kept
   it under the call's number, and none when it could not be written down *)
fn _write_text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_backup_file_write_text(resolver_id)
in
  if handle <= 0 then $R.none() else _claimed(handle)
end

fn _free_write_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* JS's codes: 1 the plugin wrote the file, 0 no plugin here, -2 the plugin
   rejected the write, -3 the write threw (the text of -2 and -3 kept by the
   call's number); any other is a code JS never gives *)
fn _backup_write_answer (code: Int, resolver_id: int): backup_write_answer =
  if code = 1 then BackupWriteDone()
  else if code = 0 then BackupWriteNotHere()
  else if code = ~2 then BackupWriteRejected(_write_text(resolver_id))
  else if code = ~3 then BackupWriteThrown(_write_text(resolver_id))
  else BackupWriteUnexpected(code)

(* The old outcome, as it always was: written when the plugin answered the
   write (whatever it answered); BackupNotWritten for no plugin here, a
   write rejected or thrown (the text freed). The one change: the name or
   the bytes failing to read or encode threw out of the import before; it is
   a thrown write now, so BackupNotWritten *)
fn _written (answer: backup_write_answer): backup_written =
  case+ answer of
  | ~BackupWriteDone() => BackupWritten()
  | ~BackupWriteNotHere() => BackupNotWritten()
  | ~BackupWriteRejected(text) => let val () = _free_write_text(text) in BackupNotWritten() end
  | ~BackupWriteThrown(text) => let val () = _free_write_text(text) in BackupNotWritten() end
  | ~BackupWriteUnexpected(_) => BackupNotWritten()

(* Answers nobody took. Before their first use. *)
implement $P.dispose<backup_written>(_) = ()
implement $P.dispose<backup_write_answer>(answer) =
  case+ answer of
  | ~BackupWriteDone() => ()
  | ~BackupWriteNotHere() => ()
  | ~BackupWriteRejected(text) => _free_write_text(text)
  | ~BackupWriteThrown(text) => _free_write_text(text)
  | ~BackupWriteUnexpected(_) => ()
implement $P.dispose<backup_found>(found) =
  case+ found of
  | ~BackupFound(blob) => blob_free(blob)
  | ~BackupNone() => ()
  | ~BackupUnreadable() => ()

implement backup_file_available() = _bats_js_backup_file_available() > 0

implement backup_file_write_answer{ln}{nn}{lb}{nb}(name, name_len, bytes, len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_backup_file_write(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, name_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(bytes) end, len, id)
in $P.and_then<Int><backup_write_answer>(p, llam (code) =>
  $P.ret<backup_write_answer>(_backup_write_answer(code, id))) end

implement backup_file_write{ln}{nn}{lb}{nb}(name, name_len, bytes, len) =
  $P.and_then<backup_write_answer><backup_written>(
    backup_file_write_answer(name, name_len, bytes, len), llam (answer) =>
    $P.ret<backup_written>(_written(answer)))

implement backup_file_read{ln}{nn}(name, name_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_backup_file_read(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, name_len, id)
in $P.and_then<Int><backup_found>(p, llam (code) =>
  $P.ret<backup_found>(_backup_found(code))) end

end (* #target wasm *)
