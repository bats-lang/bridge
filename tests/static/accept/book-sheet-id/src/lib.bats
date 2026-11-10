#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload BC = "wasm.bats-packages.dev/bridge/src/book_content.bats"

(* A sheet with the container's id written through book_sheet_id: the selector
   prefix [data-book-container="<id>"], the id's own bytes, a rule. Nothing of
   outside bytes is used, and the old forms (book_sheet_lit, book_sheet_end)
   are beside it *)
fn f {lc:agz}{nc:pos | nc <= 64}
  (s: !$BC.book_stream, container: !$A.borrow(byte, lc, nc), n: int nc): void = let
  val () = $BC.book_sheet_lit(s, container, n, "[data-book-container=\"")
  val () = $BC.book_sheet_id(s, container, n)
  val () = $BC.book_sheet_lit(s, container, n, "\"] p{margin:0}")
in $BC.book_sheet_end(s, container, n) end
