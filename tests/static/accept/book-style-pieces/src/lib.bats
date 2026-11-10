#include "share/atspre_staload.hats"
#use array as A
#use wasm.bats-packages.dev/bridge as B
staload OU = "wasm.bats-packages.dev/bridge/src/outside.bats"
staload BC = "wasm.bats-packages.dev/bridge/src/book_content.bats"

(* The style of a book element written in pieces: a literal (a property name
   and its colon), a span of outside bytes (the value), a literal (the
   semicolon), then the end; the container and the element id are the same
   two borrows in every call. The old form (book_style) is beside it *)
fn f {l:agz}{n:nat}{cs:$A.cells}{lc:agz}{nc:pos | nc <= 64}{li:agz}{ni:pos | ni <= 1024}{o,k:nat | o + k <= n; k <= 65535}
  (pf: $OU.OUTSIDE_READ(cs) |
   s: !$BC.book_stream, doc: !$A.cborrow(l, n, cs),
   container: !$A.borrow(byte, lc, nc), cn: int nc,
   id: !$A.borrow(byte, li, ni), idn: int ni, off: int o, len: int k): void = let
  val run = $BC.book_style_begin(container, id)
  val () = $BC.book_style_lit(s, run, container, cn, id, idn, "color:")
  val () = $BC.book_style_span(pf | s, run, container, cn, id, idn, doc, off, len)
  val () = $BC.book_style_lit(s, run, container, cn, id, idn, ";")
in $BC.book_style_end(s, run, container, cn, id, idn) end
