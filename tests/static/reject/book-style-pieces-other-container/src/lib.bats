#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload BC = "wasm.bats-packages.dev/bridge/src/book_content.bats"

(* A piece of the style of an element of the container, given the borrow of a
   different container: the run fixes the container *)
fn f {lc:agz}{lo:agz}{li:agz}{nc:pos | nc <= 64}{ni:pos | ni <= 1024}
  (s: !$BC.book_stream, container: !$A.borrow(byte, lc, nc), other: !$A.borrow(byte, lo, nc), cn: int nc,
   id: !$A.borrow(byte, li, ni), idn: int ni): void = let
  val run = $BC.book_style_begin(container, id)
  val () = $BC.book_style_lit(s, run, other, cn, id, idn, "color:red")
in $BC.book_style_end(s, run, container, cn, id, idn) end
