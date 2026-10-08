#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R
#use wasm.bats-packages.dev/bridge as B
staload ID = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DC = "wasm.bats-packages.dev/bridge/src/decompress.sats"

(* A cause matched without ReadFailed: a request that errored would go
   unhandled, as if the database had opened *)
fn f (cause: $ID.unreadable_cause): void =
  case+ cause of
  | ~$ID.NoDatabase(reason) => $ID.browser_reason_free(reason)
  | ~$ID.UnreadableUnexpected(_, _) => ()
