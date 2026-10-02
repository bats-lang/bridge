#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* Taking the body lets the response go: its status cannot be read
   after *)
fn f (got: $FE.fetched): int =
  case+ got of
  | ~$FE.NoResponse() => 0
  | ~$FE.Responded(r) => let
      val () = $BD.blob_free($FE.fetch_body(r))
    in $FE.fetch_status(r) end
