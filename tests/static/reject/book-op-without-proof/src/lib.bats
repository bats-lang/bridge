#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload OU = "wasm.bats-packages.dev/bridge/src/outside.bats"
staload BC = "wasm.bats-packages.dev/bridge/src/book_content.bats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.bats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.bats"
staload ID = "wasm.bats-packages.dev/bridge/src/idb.bats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.bats"

(* A sheet piece from bytes the program made: there is no proof to pass *)
fn f {n:pos | n <= 1048576}{lc:agz}
  (n: int n, container: !$A.borrow(byte, lc, 1)): void = let
  val @(pfm | bm) = $A.barr_of_arr($A.alloc<byte>(n))
  val @(fz, cb) = $A.barr_freeze(bm)
  val s = $BC.book_stream_new()
  val () = $BC.book_sheet_span(pfm | s, container, 1, cb, 0, 1)
  val () = $BC.book_stream_free(s)
  val () = $A.cborrow_drop(fz, cb)
in $A.free<byte>($A.barr_to_arr($A.barr_thaw(fz))) end
