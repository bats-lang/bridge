#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A compression matched without DeflateRaw *)
fn f (method: $DC.compression): int =
  case+ method of
  | $DC.Uncompressed() => 0
  | $DC.Gzip() => 1
  | $DC.Deflate() => 2
