(* share -- sharing text and files for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* How a share ended. JS's answer is decoded here, once: a code it
   should not send is ShareFailed.
   Deprecated (share, bridge#241): it folds a failure the Web Share API
   documents, no way to share here, a share rejected with anything else and
   a share that threw into ShareFailed; text_share_answer tells them apart. *)
#pub datatype share_outcome =
  | Shared       (* the share sheet took it *)
  | Cancelled    (* the user closed the share sheet *)
  | ShareFailed  (* it failed, or text cannot be shared here *)

(* How a file's share ended: share_outcome's cases, and one more, for a
   platform that cannot share this file at all (the app may then share
   its text instead). A code JS should not send is FileShareFailed.
   Deprecated (share, bridge#242): it folds a failure the Web Share API
   documents, a write to the cache the plugin rejected, a share rejected
   with anything else and a share that threw into FileShareFailed;
   file_share_answer tells them apart. *)
#pub datatype file_share_outcome =
  | FileShared
  | FileShareCancelled
  | FileShareFailed
  | FilesNotShareable

(* How a text's share ended, each outcome its own. JS's answer is decoded
   here, once: shared; cancelled (the platform's cancel: an AbortError, or
   the Share plugin's "Share canceled"); failed as the Web Share API
   documents (NotAllowedError, DataError, TypeError); no way to share here;
   rejected with anything else; the share threw (the call, or reading the
   text or the title); and a code JS never gives. The texts are what the
   share was rejected with or threw, written down by JS, none when it could
   not. Linear, so the one consumer takes it apart with case+ ~; one no
   consumer takes is freed by promise's dispose. *)
#pub datavtype text_share_answer =
  | TextAnswerShared                                       (* the share sheet took it *)
  | TextAnswerCancelled                                    (* the user closed the share sheet *)
  | TextAnswerFailed of $R.option([n:nat] dblob(n))        (* a failure the Web Share API documents: what, as text *)
  | TextAnswerNotHere                                      (* no way to share text here *)
  | TextAnswerRejected of $R.option([n:nat] dblob(n))      (* rejected with anything else: what, as text *)
  | TextAnswerThrown of $R.option([n:nat] dblob(n))        (* the share threw: what, as text *)
  | TextAnswerUnexpected of Int                            (* a code JS never gives *)

(* How a file's share ended, each outcome its own: text_share_answer's
   cases, and for the app, the file's write to its cache rejected (what, as
   text), and a platform that cannot share this file at all (the app may
   then share its text instead). *)
#pub datavtype file_share_answer =
  | FileAnswerShared
  | FileAnswerCancelled
  | FileAnswerFailed of $R.option([n:nat] dblob(n))        (* a failure the Web Share API documents: what, as text *)
  | FileAnswerNotShareable                                 (* this platform cannot share this file *)
  | FileAnswerRejected of $R.option([n:nat] dblob(n))      (* the share rejected with anything else: what, as text *)
  | FileAnswerCacheRejected of $R.option([n:nat] dblob(n)) (* the write to the app's cache rejected: what, as text *)
  | FileAnswerThrown of $R.option([n:nat] dblob(n))        (* the share threw: what, as text *)
  | FileAnswerUnexpected of Int                            (* a code JS never gives *)

(* Whether text can be shared here. Browser: navigator.share. App
   (Capacitor): the Share plugin. *)
#pub fun share_available(): bool

(* Whether files can be shared here. Browser: navigator.canShare says
   files can be (a text file is asked about; a type a browser refuses is
   answered by share_file). App: the Share and Filesystem plugins (the
   file is written to the app's cache, and its URI shared). *)
#pub fun share_file_available(): bool

(* Shares text[0, text_len), with title[0, title_len) (none when
   title_len is 0), through the system's share sheet (browser, else the
   app's plugin). Call it from a click's listener (a browser needs the
   user's activation). The promise resolves with how it ended.
   Deprecated (share, bridge#241): share_text_answer. *)
#pub fun share_text
  {lt:agz}{nt:pos}{kt:nat | kt <= nt}{lx:agz}{nx:pos}
  (title: !$A.borrow(byte, lt, nt), title_len: int kt,
   text: !$A.borrow(byte, lx, nx), text_len: int nx)
  : $P.promise(share_outcome, $P.Chained)

(* share_text with every outcome its own *)
#pub fun share_text_answer
  {lt:agz}{nt:pos}{kt:nat | kt <= nt}{lx:agz}{nx:pos}
  (title: !$A.borrow(byte, lt, nt), title_len: int kt,
   text: !$A.borrow(byte, lx, nx), text_len: int nx)
  : $P.promise(text_share_answer, $P.Chained)

(* Shares a file named name, of type mime, holding bytes[0, len), as
   share_text (browser: navigator.share with the file; app: Share and
   Filesystem). The promise resolves with how it ended:
   FilesNotShareable when this platform cannot share this file.
   Deprecated (share, bridge#242): share_file_answer. *)
#pub fun share_file
  {ln:agz}{nn:pos}{lb:agz}{nb:pos}{lm:agz}{nm:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm)
  : $P.promise(file_share_outcome, $P.Chained)

(* share_file with every outcome its own *)
#pub fun share_file_answer
  {ln:agz}{nn:pos}{lb:agz}{nb:pos}{lm:agz}{nm:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm)
  : $P.promise(file_share_answer, $P.Chained)

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern int bats_js_share_available(void);
extern int bats_js_share_file_available(void);
extern void bats_js_share_text(void*, int, void*, int, int);
extern void bats_js_share_file(void*, int, void*, int, void*, int, int);
extern int bats_js_share_said_text(int);
%}
extern fun _bats_js_share_available
  (): int = "mac#bats_js_share_available"
extern fun _bats_js_share_file_available
  (): int = "mac#bats_js_share_file_available"
extern fun _bats_js_share_text
  (title: ptr, title_len: int, text: ptr, text_len: int, resolver_id: int)
  : void = "mac#bats_js_share_text"
extern fun _bats_js_share_file
  (name: ptr, name_len: int, bytes: ptr, len: int,
   mime: ptr, mime_len: int, resolver_id: int)
  : void = "mac#bats_js_share_file"
extern fun _bats_js_share_said_text
  (resolver_id: int): int = "mac#bats_js_share_said_text"
end

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

(* What a share was rejected with, or what threw, as text: JS kept it under
   the call's number, and none when it could not be written down *)
fn _said_text (resolver_id: int): $R.option([n:nat] dblob(n)) = let
  val handle = _bats_js_share_said_text(resolver_id)
in
  if handle <= 0 then $R.none() else _claimed(handle)
end

fn _free_text (text: $R.option([n:nat] dblob(n))): void =
  case+ text of ~$R.some(blob) => blob_free(blob) | ~$R.none() => ()

(* JS's codes: 0 shared, 1 cancelled, 2 failed as the Web Share API
   documents, 3 no way to share here (for a file, this platform cannot
   share it), -2 rejected with anything else, -3 threw, -4 (a file only)
   the write to the app's cache rejected (the text of 2, -2, -3 and -4 kept
   by the call's number); any other is a code JS never gives *)
fn _text_share_answer (code: Int, resolver_id: int): text_share_answer =
  if code = 0 then TextAnswerShared()
  else if code = 1 then TextAnswerCancelled()
  else if code = 2 then TextAnswerFailed(_said_text(resolver_id))
  else if code = 3 then TextAnswerNotHere()
  else if code = ~2 then TextAnswerRejected(_said_text(resolver_id))
  else if code = ~3 then TextAnswerThrown(_said_text(resolver_id))
  else TextAnswerUnexpected(code)

fn _file_share_answer (code: Int, resolver_id: int): file_share_answer =
  if code = 0 then FileAnswerShared()
  else if code = 1 then FileAnswerCancelled()
  else if code = 2 then FileAnswerFailed(_said_text(resolver_id))
  else if code = 3 then FileAnswerNotShareable()
  else if code = ~2 then FileAnswerRejected(_said_text(resolver_id))
  else if code = ~3 then FileAnswerThrown(_said_text(resolver_id))
  else if code = ~4 then FileAnswerCacheRejected(_said_text(resolver_id))
  else FileAnswerUnexpected(code)

(* The old outcomes, as they always were: shared, cancelled, and failed for
   everything else (the text freed); for a file, one more for a platform
   that cannot share it. Two changes: what is neither an AbortError nor the
   Share plugin's "Share canceled" is no cancel now (the old JS took any
   message with "cancel" in it for one: such a rejection is a failure here
   and is its own outcome in the new form), and reading the text, the title,
   the name, the bytes or the type, which threw out of the import before
   (the promise never settled), is a thrown share now, so failed *)
fn _share_outcome (answer: text_share_answer): share_outcome =
  case+ answer of
  | ~TextAnswerShared() => Shared()
  | ~TextAnswerCancelled() => Cancelled()
  | ~TextAnswerFailed(text) => let val () = _free_text(text) in ShareFailed() end
  | ~TextAnswerNotHere() => ShareFailed()
  | ~TextAnswerRejected(text) => let val () = _free_text(text) in ShareFailed() end
  | ~TextAnswerThrown(text) => let val () = _free_text(text) in ShareFailed() end
  | ~TextAnswerUnexpected(_) => ShareFailed()

fn _file_share_outcome (answer: file_share_answer): file_share_outcome =
  case+ answer of
  | ~FileAnswerShared() => FileShared()
  | ~FileAnswerCancelled() => FileShareCancelled()
  | ~FileAnswerFailed(text) => let val () = _free_text(text) in FileShareFailed() end
  | ~FileAnswerNotShareable() => FilesNotShareable()
  | ~FileAnswerRejected(text) => let val () = _free_text(text) in FileShareFailed() end
  | ~FileAnswerCacheRejected(text) => let val () = _free_text(text) in FileShareFailed() end
  | ~FileAnswerThrown(text) => let val () = _free_text(text) in FileShareFailed() end
  | ~FileAnswerUnexpected(_) => FileShareFailed()

implement share_available() = _bats_js_share_available() > 0

implement share_file_available() = _bats_js_share_file_available() > 0

(* Outcomes nobody took: nothing to free. ATS2 resolves a template's
   instances in file order, so these come before their first use. *)
implement $P.dispose<share_outcome>(_) = ()
implement $P.dispose<file_share_outcome>(_) = ()
implement $P.dispose<text_share_answer>(answer) =
  case+ answer of
  | ~TextAnswerShared() => ()
  | ~TextAnswerCancelled() => ()
  | ~TextAnswerFailed(text) => _free_text(text)
  | ~TextAnswerNotHere() => ()
  | ~TextAnswerRejected(text) => _free_text(text)
  | ~TextAnswerThrown(text) => _free_text(text)
  | ~TextAnswerUnexpected(_) => ()
implement $P.dispose<file_share_answer>(answer) =
  case+ answer of
  | ~FileAnswerShared() => ()
  | ~FileAnswerCancelled() => ()
  | ~FileAnswerFailed(text) => _free_text(text)
  | ~FileAnswerNotShareable() => ()
  | ~FileAnswerRejected(text) => _free_text(text)
  | ~FileAnswerCacheRejected(text) => _free_text(text)
  | ~FileAnswerThrown(text) => _free_text(text)
  | ~FileAnswerUnexpected(_) => ()

implement share_text_answer{lt}{nt}{kt}{lx}{nx}(title, title_len, text, text_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_share_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end, title_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len, id)
in $P.and_then<Int><text_share_answer>(p, llam (code) =>
  $P.ret<text_share_answer>(_text_share_answer(code, id))) end

implement share_text{lt}{nt}{kt}{lx}{nx}(title, title_len, text, text_len) =
  $P.and_then<text_share_answer><share_outcome>(
    share_text_answer(title, title_len, text, text_len), llam (answer) =>
    $P.ret<share_outcome>(_share_outcome(answer)))

implement share_file_answer{ln}{nn}{lb}{nb}{lm}{nm}
  (name, name_len, bytes, len, mime, mime_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_share_file(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, name_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(bytes) end, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len, id)
in $P.and_then<Int><file_share_answer>(p, llam (code) =>
  $P.ret<file_share_answer>(_file_share_answer(code, id))) end

implement share_file{ln}{nn}{lb}{nb}{lm}{nm}
  (name, name_len, bytes, len, mime, mime_len) =
  $P.and_then<file_share_answer><file_share_outcome>(
    share_file_answer(name, name_len, bytes, len, mime, mime_len), llam (answer) =>
    $P.ret<file_share_outcome>(_file_share_outcome(answer)))

end (* #target wasm *)
