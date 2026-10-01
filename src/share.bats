(* share -- sharing text and files for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

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
   user's activation). The promise resolves with 0 once it is shared, 1
   when the user cancelled, 2 when it failed or cannot be shared here. *)
#pub fun share_text
  {lt:agz}{nt:pos}{kt:nat | kt <= nt}{lx:agz}{nx:pos}
  (title: !$A.borrow(byte, lt, nt), title_len: int kt,
   text: !$A.borrow(byte, lx, nx), text_len: int nx)
  : $P.promise_pending(Int)

(* Shares a file named name, of type mime, holding bytes[0, len), as
   share_text (browser: navigator.share with the file; app: Share and
   Filesystem). The promise resolves as share_text's, or with 3 when this
   platform cannot share this file (the app may share its text instead). *)
#pub fun share_file
  {ln:agz}{nn:pos}{lb:agz}{nb:pos}{lm:agz}{nm:pos}
  (name: !$A.borrow(byte, ln, nn), name_len: int nn,
   bytes: !$A.borrow(byte, lb, nb), len: int nb,
   mime: !$A.borrow(byte, lm, nm), mime_len: int nm)
  : $P.promise_pending(Int)

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

implement share_available() = _bats_js_share_available() > 0

implement share_file_available() = _bats_js_share_file_available() > 0

implement share_text{lt}{nt}{kt}{lx}{nx}(title, title_len, text, text_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_share_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(title) end, title_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len, id)
in p end

implement share_file{ln}{nn}{lb}{nb}{lm}{nm}
  (name, name_len, bytes, len, mime, mime_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_share_file(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(name) end, name_len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(bytes) end, len,
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(mime) end, mime_len, id)
in p end

end (* #target wasm *)
