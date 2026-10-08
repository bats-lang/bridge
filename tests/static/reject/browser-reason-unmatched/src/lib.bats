#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload ID = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* What the browser said, matched without StorageBlocked: a private
   window or blocked site data would go unhandled, as if it were
   another failure *)
fn f (reason: $ID.browser_reason): void =
  case+ reason of
  | ~$ID.Transient() => ()
  | ~$ID.NewerVersion() => ()
  | ~$ID.Aborted() => ()
  | ~$ID.NoErrorGiven() => ()
  | ~$ID.BrowserUnexpected(blob) => $DC.blob_free(blob)
