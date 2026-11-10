#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload BC = "wasm.bats-packages.dev/bridge/src/book_content.bats"

(* The id written is the container operand's own bytes: the id of a different
   container cannot be given beside it *)
fn f {lc:agz}{lo:agz}{nc:pos | nc <= 64}
  (s: !$BC.book_stream, container: !$A.borrow(byte, lc, nc), other: !$A.borrow(byte, lo, nc), n: int nc): void =
  $BC.book_sheet_id(s, container, n, other, n)
