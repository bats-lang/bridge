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

(* file_store holds bytes the program wrote: an infile, not an infile_outside *)
fn f {n:pos | n <= 1048576}{lb:agz}
  (data: !$A.borrow(byte, lb, n), n: int n): void = let
  val file = $BF.file_store(data, n)
  val out = $A.alloc<byte>(n)
  val @(pfo, pfc, pflent | ba) = $OU.file_read_outside(file, 0, out, n)
in () end
