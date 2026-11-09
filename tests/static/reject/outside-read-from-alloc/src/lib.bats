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

(* An array the program allocated is not the file's: barr_of_arr gives it cells
   of its own, so the file's proof does not apply to it *)
fn f {n:pos | n <= 1048576}{lc:agz}
  (file: !$OU.infile_outside(n), n: int n, container: !$A.borrow(byte, lc, 1)): void = let
  val a = $A.alloc<byte>(n)
  val @(pfo, pfc, pflent | ba) = $OU.file_read_outside(file, 0, a, n)
  val back = $A.barr_to_arrx(pflent | ba)
  val @(pfm | bm) = $A.barr_of_arr($A.alloc<byte>(n))
  val @(fz, cb) = $A.barr_freeze(bm)
  val s = $BC.book_stream_new()
  val () = $BC.book_sheet_span(pfo | s, container, 1, cb, 0, 1)
  val () = $BC.book_stream_free(s)
  val () = $A.cborrow_drop(fz, cb)
  val () = $A.free<byte>($A.barr_to_arr($A.barr_thaw(fz)))
in $A.free<byte>(back) end
