(* share -- sharing text and files for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

(* How a share ended. JS's answer is decoded here, once: a code it
   should not send is ShareFailed. *)
#pub datatype share_outcome =
  | Shared       (* the share sheet took it *)
  | Cancelled    (* the user closed the share sheet *)
  | ShareFailed  (* it failed, or text cannot be shared here *)

(* How a file's share ended: share_outcome's cases, and one more, for a
   platform that cannot share this file at all (the app may then share
   its text instead). A code JS should not send is FileShareFailed. *)
#pub datatype file_share_outcome =
  | FileShared
  | FileShareCancelled
  | FileShareFailed
  | FilesNotShareable

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
   user's activation). The promise resolves with how it ended. *)
#pub fun share_text
  {lt:agz}{nt:pos}{kt:nat | kt <= nt}{lx:agz}{nx:pos}
  (title: !$A.borrow(byte, lt, nt), title_len: int kt,
   text: !$A.borrow(byte, lx, nx), text_len: int nx)
  : $P.promise(share_outcome, $P.Chained)

(* Shares a file named name, of type mime, holding bytes[0, len), as
   share_text (browser: navigator.share with the file; app: Share and
   Filesystem). The promise resolves with how it ended:
   FilesNotShareable when this platform cannot share this file. *)
#pub fun share_file
  {ln:agz}{nn:pos}{lb:agz}{nb:pos}{lm:agz}{nm:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm)
  : $P.promise(file_share_outcome, $P.Chained)

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
end

(* JS's codes: 0 shared, 1 cancelled, 2 failed, 3 a file this platform
   cannot share *)
fn _share_outcome (code: Int): share_outcome =
  if code = 0 then Shared()
  else if code = 1 then Cancelled()
  else ShareFailed()

fn _file_share_outcome (code: Int): file_share_outcome =
  if code = 0 then FileShared()
  else if code = 1 then FileShareCancelled()
  else if code = 3 then FilesNotShareable()
  else FileShareFailed()

implement share_available() = _bats_js_share_available() > 0

implement share_file_available() = _bats_js_share_file_available() > 0

(* Outcomes nobody took: nothing to free. ATS2 resolves a template's
   instances in file order, so these come before their first use. *)
implement $P.dispose<share_outcome>(_) = ()
implement $P.dispose<file_share_outcome>(_) = ()

implement share_text{lt}{nt}{kt}{lx}{nx}(title, title_len, text, text_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_share_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end, title_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len, id)
in $P.and_then<Int><share_outcome>(p, llam (code) =>
  $P.ret<share_outcome>(_share_outcome(code))) end

implement share_file{ln}{nn}{lb}{nb}{lm}{nm}
  (name, name_len, bytes, len, mime, mime_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_share_file(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, name_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(bytes) end, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len, id)
in $P.and_then<Int><file_share_outcome>(p, llam (code) =>
  $P.ret<file_share_outcome>(_file_share_outcome(code))) end

end (* #target wasm *)
