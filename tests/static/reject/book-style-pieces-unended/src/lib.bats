#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload BC = "wasm.bats-packages.dev/bridge/src/book_content.bats"

(* A style written in pieces and never ended: the run is linear and only
   book_style_end consumes it *)
fn f {lc:agz}{li:agz}{nc:pos | nc <= 64}{ni:pos | ni <= 1024}
  (s: !$BC.book_stream, container: !$A.borrow(byte, lc, nc), cn: int nc,
   id: !$A.borrow(byte, li, ni), idn: int ni): void = let
  val run = $BC.book_style_begin(container, id)
in $BC.book_style_lit(s, run, container, cn, id, idn, "color:red") end
