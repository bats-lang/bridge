(* clipboard -- clipboard read/write for bridge *)

#include "share/atspre_staload.hats"

#use array as A
#use promise as P

(* ============================================================
   Public API
   ============================================================ *)

#pub fun clipboard_write
  {lb:agz}{n:nat}
  (text: !$A.borrow(byte, lb, n), text_len: int n)
  : $P.promise(int, $P.Pending)

#pub fun clipboard_read
  (): $P.promise(int, $P.Pending)

#pub fun clipboard_read_result
  {n:pos | n <= 1048576}
  (len: int n): [l:agz] $A.arr(byte, l, n)

#pub fun on_clipboard_complete
  (resolver_id: int, success: int): void = "ext#bats_on_clipboard_complete"

#pub fun on_clipboard_read_complete
  (resolver_id: int, text_len: int): void = "ext#bats_on_clipboard_read_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

extern fun _bats_js_clipboard_write_text
  (text: ptr, text_len: int, resolver_id: int)
  : void = "mac#bats_js_clipboard_write_text"
extern fun _bats_js_clipboard_read_text
  (resolver_id: int): void = "mac#bats_js_clipboard_read_text"

implement clipboard_write{lb}{n}(text, text_len) = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_clipboard_write_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    id)
in p end

implement clipboard_read() = let
  val @(p, r) = $P.create<int>()
  val id = $P.stash(r)
  val () = _bats_js_clipboard_read_text(id)
in p end

implement clipboard_read_result{n}(len) =
  stash_read(stash_get_int(1), len)

implement on_clipboard_complete(resolver_id, success) =
  $P.fire(resolver_id, success)

implement on_clipboard_read_complete(resolver_id, text_len) =
  $P.fire(resolver_id, text_len)

end (* #target wasm *)
