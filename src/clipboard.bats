(* clipboard -- clipboard read/write for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun clipboard_write
  : {lb:agz}{n:nat}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise_pending(Int)

(* Reads the clipboard's text: the promise resolves with a handle to
   claim with blob_claim (decompress.bats), 0 when there is none *)
#pub fun clipboard_read
  : () -> $P.promise_pending(Int)

#pub fun on_clipboard_complete
  (resolver_id: int, success: Int): void = "ext#bats_on_clipboard_complete"

#pub fun on_clipboard_read_complete
  (resolver_id: int, handle: Int): void = "ext#bats_on_clipboard_read_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin
$UNSAFE begin
%{
extern void bats_js_clipboard_write_text(void*, int, int);
extern void bats_js_clipboard_read_text(int);
%}
extern fun _bats_js_clipboard_write_text
  (text: ptr, text_len: int, resolver_id: int)
  : void = "mac#bats_js_clipboard_write_text"
extern fun _bats_js_clipboard_read_text
  (resolver_id: int): void = "mac#bats_js_clipboard_read_text"
end

implement clipboard_write{lb}{n}(text, text_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_clipboard_write_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    id)
in p end

implement clipboard_read() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_clipboard_read_text(id)
in p end

implement on_clipboard_complete(resolver_id, success) =
  $P.fire(resolver_id, success)

implement on_clipboard_read_complete(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
