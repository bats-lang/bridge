#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload CL = "wasm.bats-packages.dev/bridge/src/clipboard.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A clipboard read matched without ClipRefused *)
fn f (): void =
  $P.finish<$CL.clip>($CL.clipboard_read(), llam (found) =>
    case+ found of
    | ~$CL.Clipped(blob) => $DC.blob_free(blob)
    | ~$CL.ClipEmpty() => ())
