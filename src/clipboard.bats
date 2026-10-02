(* clipboard -- clipboard read/write for bridge *)

#include "share/atspre_staload.hats"
staload "./decompress.bats"

#use array as A
#use promise as P
#use result as R

(* ============================================================
   Public API
   ============================================================ *)

(* Whether text was put on the clipboard. JS's answer is decoded here,
   once: anything but its 1 is NotCopied. *)
#pub datatype copied =
  | Copied
  | NotCopied

#pub fun clipboard_write
  : {lb:agz}{n:nat}
  (!$A.borrow(byte, lb, n), int n) -> $P.promise(copied, $P.Chained)

(* What reading the clipboard found. Empty and refused are told apart:
   ClipEmpty is a clipboard with no text; ClipRefused is a read the
   browser refused (no permission, no clipboard here) or that failed.
   Linear: Clipped holds a blob JS keeps until it is freed, so the one
   consumer frees it; a clip no consumer takes is freed by promise's
   dispose. *)
#pub datavtype clip =
  | Clipped of ([n:pos] dblob(n))
  | ClipEmpty
  | ClipRefused

(* Reads the clipboard's text *)
#pub fun clipboard_read
  : () -> $P.promise(clip, $P.Chained)

#pub fun on_clipboard_complete
  (resolver_id: int, success: Int): void = "ext#bats_on_clipboard_complete"

#pub fun on_clipboard_read_complete
  (resolver_id: int, handle: Int): void = "ext#bats_on_clipboard_read_complete"

(* ============================================================
   WASM implementation
   ============================================================ *)

#target wasm begin

(* JS's code for a blob, as a handle: bridge's own atoms are the only
   ones that give one *)
fn _claimed_blob (code: int): $R.option([n:nat] dblob(n)) =
  blob_claim($UNSAFE begin $UNSAFE.cast{blob_handle}(code) end)

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

(* JS's codes: 1 copied, 0 not *)
fn _copied (code: Int): copied =
  if code = 1 then Copied() else NotCopied()

(* An outcome nobody took: nothing to free. Before clipboard_write, its
   first use. *)
implement $P.dispose<copied>(_) = ()

implement clipboard_write{lb}{n}(text, text_len) = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_clipboard_write_text(
    $UNSAFE begin $UNSAFE.castvwtp1{ptr}(text) end, text_len,
    id)
in $P.and_then<Int><copied>(p, llam (code) => $P.ret<copied>(_copied(code))) end

(* JS's codes: a blob's handle (positive), 0 no text, anything else
   (its -1) refused. A handle JS did not hand out, or an empty blob, is
   refused too: JS's word is checked here, once *)
fn _clip (code: Int): clip =
  if code = 0 then ClipEmpty()
  else if code < 0 then ClipRefused()
  else (case+ _claimed_blob(code) of
    | ~$R.some(blob) =>
      if blob_len(blob) > 0 then Clipped(blob)
      else let val () = blob_free(blob) in ClipRefused() end
    | ~$R.none() => ClipRefused())

(* A clip nobody took: its blob is freed. Before clipboard_read, its
   first use. *)
implement $P.dispose<clip>(found) =
  case+ found of
  | ~Clipped(blob) => blob_free(blob)
  | ~ClipEmpty() => ()
  | ~ClipRefused() => ()

implement clipboard_read() = let
  val @(p, r) = $P.create<Int>()
  val id = $P.stash(r)
  val () = _bats_js_clipboard_read_text(id)
in $P.and_then<Int><clip>(p, llam (code) => $P.ret<clip>(_clip(code))) end

implement on_clipboard_complete(resolver_id, success) =
  $P.fire(resolver_id, success)

implement on_clipboard_read_complete(resolver_id, handle) =
  $P.fire(resolver_id, handle)

end (* #target wasm *)
