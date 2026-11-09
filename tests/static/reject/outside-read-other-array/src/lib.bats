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

(* The proof of one outside file is not the proof of another's cells *)
fn f {n:pos | n <= 1048576}{lc:agz}
  (one: !$OU.infile_outside(n), two: !$OU.infile_outside(n), n: int n, container: !$A.borrow(byte, lc, 1)): void = let
  val a = $A.alloc<byte>(n)
  val @(pfo, pfc, pflent | ba) = $OU.file_read_outside(one, 0, a, n)
  val b = $A.alloc<byte>(n)
  val @(pf2, pfc2, pflent2 | bb) = $OU.file_read_outside(two, 0, b, n)
  val @(fz, cb) = $A.barr_freeze(bb)
  val s = $BC.book_stream_new()
  val () = $BC.book_sheet_span(pfo | s, container, 1, cb, 0, 1)
  val () = $BC.book_stream_free(s)
  val () = $A.cborrow_drop(fz, cb)
  val back2 = $A.barr_to_arrx(pflent2 | $A.barr_thaw(fz))
  val () = $A.free<byte>(back2)
in $A.free<byte>($A.barr_to_arrx(pflent | ba)) end
