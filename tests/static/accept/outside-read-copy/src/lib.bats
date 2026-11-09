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

(* A copy of an outside array holds the same cells (barr_copy), so the proof
   still applies to it *)
fn f {n:pos | n <= 1048576}{lc:agz}
  (file: !$OU.infile_outside(n), n: int n, container: !$A.borrow(byte, lc, 1)): void = let
  val a = $A.alloc<byte>(n)
  val @(pfo, pfc, pflent | ba) = $OU.file_read_outside(file, 0, a, n)
  val copy = $A.barr_copy(ba, n)
  val @(cz, cc) = $A.barr_freeze(copy)
  val s = $BC.book_stream_new()
  val () = $BC.book_sheet_span(pfo | s, container, 1, cc, 0, 1)
  val () = $BC.book_stream_free(s)
  val () = $A.cborrow_drop(cz, cc)
  val () = $A.free<byte>($A.barr_to_arr($A.barr_thaw(cz)))
  val back = $A.barr_to_arrx(pflent | ba)
in $A.free<byte>(back) end
