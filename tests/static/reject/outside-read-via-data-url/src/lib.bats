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

(* fetch_file of a data: URL gives an infile, which is not an infile_outside: a
   data: URL is the bytes themselves, and only fetch_outside, which refuses it,
   gives outside bytes *)
fn f {lb:agz}{n:pos}(url: !$A.borrow(byte, lb, n), n: int n): void =
  $P.finish<$FE.fetched_file>($FE.fetch_file(url, n), llam (got) =>
    case+ got of
    | ~$FE.RespondedFile(status, file) => let
        val m = $BF.file_size(file)
        val out = $A.alloc<byte>(1)
        val @(pfo, pfc, pflent | ba) = $OU.file_read_outside(file, 0, out, 1)
      in () end
    | ~$FE.NoFileResponse() => ())
