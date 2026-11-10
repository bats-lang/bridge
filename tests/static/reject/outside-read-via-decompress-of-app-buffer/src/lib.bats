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

(* decompress of a buffer the program holds gives a plain blob, not an outside
   one: only decompress_outside, of bytes with the proof, does *)
fn f {n:pos | n <= 1048576}{lb:agz}
  (data: !$A.borrow(byte, lb, n), n: int n): void =
  $P.finish<$DC.decompressed>($DC.decompress(data, n, $DC.Gzip()), llam (got) =>
    case+ got of
    | ~$DC.Decompressed(blob) => let
        val k = $DC.blob_len(blob)
        val out = $A.alloc<byte>(k)
        val @(pfo, pfc, pflent | ba) = $OU.blob_read_outside(blob, out, k)
      in () end
    | ~$DC.DecompressFailed() => ())
