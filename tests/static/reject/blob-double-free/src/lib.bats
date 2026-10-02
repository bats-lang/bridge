#include "share/atspre_staload.hats"
#use array as A
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A blob is freed once *)
fn f (h: $BD.blob_handle): int =
  case+ $BD.blob_claim(h) of
  | ~$R.none() => 0
  | ~$R.some(b) => let
      val () = $BD.blob_free(b)
      val () = $BD.blob_free(b)
    in 1 end
