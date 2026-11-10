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

(* A value of the bats database (idb_get) is a plain blob: only the second
   database, through file_idb_get_outside, gives outside bytes *)
fn f {lk:agz}{nk:pos}(key: !$A.borrow(byte, lk, nk), nk: int nk): void =
  $P.finish<$ID.lookup>($ID.idb_get(key, nk), llam (got) =>
    case+ got of
    | ~$ID.Found(blob) => let
        val k = $DC.blob_len(blob)
        val out = $A.alloc<byte>(k)
        val @(pfo, pfc, pflent | ba) = $OU.blob_read_outside(blob, out, k)
      in () end
    | ~$ID.Absent() => ()
    | ~$ID.Unreadable(c) => ())
