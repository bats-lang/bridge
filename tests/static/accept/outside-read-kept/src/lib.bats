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

(* An outside file is read whole; the proof is kept while the bytes are read
   through the borrow (cborrow_get) and the first byte goes into a sheet piece,
   then the array is taken back *)
fn f {n:pos | n <= 1048576}{lc:agz}
  (file: !$OU.infile_outside(n), n: int n, container: !$A.borrow(byte, lc, 1)): int = let
  val a = $A.alloc<byte>(n)
  val @(pfo, pfc, pflent | ba) = $OU.file_read_outside(file, 0, a, n)
  val @(fz, cb) = $A.barr_freeze(ba)
  val @(pfn | first) = $A.cborrow_get(cb, 0)
  val s = $BC.book_stream_new()
  val () = $BC.book_sheet_span(pfo | s, container, 1, cb, 0, 1)
  val () = $BC.book_stream_free(s)
  val () = $A.cborrow_drop(fz, cb)
  val back = $A.barr_to_arrx(pflent | $A.barr_thaw(fz))
  val () = $A.free<byte>(back)
in first end
